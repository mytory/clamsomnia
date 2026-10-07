import Darwin
import Foundation

private struct SavedSleepSession: Codable {
    var originalSleepDisabled: Bool
    var deadline: Date?
    var bootTime: TimeInterval
    var ownerPID: pid_t?
}

final class SleepManager {
    static let stateURL = URL(fileURLWithPath: "/var/db/com.mytory.Clamsomnia/session.json")

    private let queue = DispatchQueue(label: "com.mytory.Clamsomnia.sleep-manager")
    private var savedSession: SavedSleepSession?
    private var clientCounts: [pid_t: Int] = [:]
    private var expiryTimer: DispatchSourceTimer?
    private var reconnectTimer: DispatchSourceTimer?
    private var pendingSleepRequestID: UUID?

    init() {
        queue.sync {
            recoverOnStartup()
        }
    }

    func connectClient(pid: pid_t) {
        queue.async {
            self.clientCounts[pid, default: 0] += 1
            self.reconnectTimer?.cancel()
            self.reconnectTimer = nil
            if var session = self.savedSession {
                session.ownerPID = pid
                self.savedSession = session
                try? self.save(session)
                self.scheduleExpiry(for: session)
            }
        }
    }

    func disconnectClient(pid: pid_t) {
        queue.async {
            guard let count = self.clientCounts[pid] else { return }
            if count > 1 {
                self.clientCounts[pid] = count - 1
                return
            }
            self.clientCounts.removeValue(forKey: pid)
            guard self.savedSession?.ownerPID == pid else { return }
            do {
                try self.restoreSavedSession()
            } catch {
                NSLog("Clamsomnia helper could not restore sleep settings after client disconnect: %@", error.localizedDescription)
                self.scheduleRestoreRetry()
            }
        }
    }

    func perform(_ requestData: Data, from pid: pid_t, reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do {
                guard self.clientCounts[pid] != nil else {
                    throw SleepManagerError.unauthorizedClient
                }
                guard requestData.count <= 4_096 else {
                    throw SleepManagerError.invalidRequest
                }
                let request = try JSONDecoder().decode(SleepHelperRequest.self, from: requestData)
                let status: SleepStatus
                switch request.operation {
                case .status:
                    status = try self.currentStatus()
                case .setEnabled:
                    guard let enabled = request.enabled else { throw SleepManagerError.invalidRequest }
                    try self.setEnabled(enabled, duration: request.duration, ownerPID: pid)
                    self.pendingSleepRequestID = nil
                    status = try self.currentStatus()
                case .setDuration:
                    guard let duration = request.duration else { throw SleepManagerError.invalidRequest }
                    try self.setDuration(duration)
                    self.pendingSleepRequestID = nil
                    status = try self.currentStatus()
                case .sleepNow:
                    try self.setEnabled(false, duration: nil, ownerPID: pid)
                    status = try self.currentStatus()
                    let requestID = UUID()
                    self.pendingSleepRequestID = requestID
                    self.queue.asyncAfter(deadline: .now() + 0.5) {
                        guard self.pendingSleepRequestID == requestID else { return }
                        self.pendingSleepRequestID = nil
                        do {
                            guard try !Self.readSleepDisabled() else { return }
                            _ = try Self.runPMSet(["sleepnow"])
                        } catch {
                            NSLog("Clamsomnia helper could not request system sleep: %@", error.localizedDescription)
                        }
                    }
                }
                let response = SleepHelperResponse(status: status)
                reply(try JSONEncoder().encode(response), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func shutdownAndRestore() {
        queue.sync {
            do {
                try restoreSavedSession()
            } catch {
                NSLog("Clamsomnia helper could not restore sleep settings during shutdown: %@", error.localizedDescription)
            }
        }
    }

    static func restoreFromDisk() throws {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return }
        let data = try Data(contentsOf: stateURL)
        let session = try JSONDecoder().decode(SavedSleepSession.self, from: data)
        if try readSleepDisabled() != session.originalSleepDisabled {
            try setSleepDisabled(session.originalSleepDisabled)
        }
        try FileManager.default.removeItem(at: stateURL)
    }

    private func recoverOnStartup() {
        guard FileManager.default.fileExists(atPath: Self.stateURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.stateURL)
            let session = try JSONDecoder().decode(SavedSleepSession.self, from: data)
            savedSession = session
            let currentBootTime = Self.currentBootTime()
            let isSameBoot = session.bootTime > 0 && currentBootTime > 0 && abs(session.bootTime - currentBootTime) < 1
            let actualState = try Self.readSleepDisabled()

            guard actualState else {
                clearSavedSession()
                return
            }

            if !isSameBoot || session.deadline.map({ $0 <= Date() }) == true {
                try restoreSavedSession()
                return
            }

            scheduleExpiry(for: session)
            scheduleReconnectRecovery()
        } catch {
            NSLog("Clamsomnia helper could not recover its saved sleep session: %@", error.localizedDescription)
            if savedSession != nil {
                scheduleStartupRecoveryRetry()
            }
        }
    }

    private func currentStatus() throws -> SleepStatus {
        if let session = savedSession, session.deadline.map({ $0 <= Date() }) == true {
            try restoreSavedSession()
        }

        let actualState = try Self.readSleepDisabled()
        if savedSession != nil, !actualState {
            clearSavedSession()
            return .disabled
        }
        if let session = savedSession {
            return SleepStatus(isEnabled: true, ownership: .app, deadline: session.deadline)
        }
        return SleepStatus(isEnabled: actualState, ownership: actualState ? .external : .none, deadline: nil)
    }

    private func setEnabled(_ enabled: Bool, duration: DurationChoice?, ownerPID: pid_t) throws {
        guard enabled else {
            if savedSession != nil {
                try restoreSavedSession()
            } else if try Self.readSleepDisabled() {
                try Self.setSleepDisabled(false)
            }
            return
        }

        let deadline = try makeDeadline(for: duration)
        if var session = savedSession {
            guard try Self.readSleepDisabled() else {
                clearSavedSession()
                return
            }
            session.deadline = deadline
            session.ownerPID = ownerPID
            try save(session)
            savedSession = session
            scheduleExpiry(for: session)
            return
        }

        guard try !Self.readSleepDisabled() else { return }
        let session = SavedSleepSession(
            originalSleepDisabled: false,
            deadline: deadline,
            bootTime: Self.currentBootTime(),
            ownerPID: ownerPID
        )
        try save(session)
        do {
            try Self.setSleepDisabled(true)
        } catch {
            try? FileManager.default.removeItem(at: Self.stateURL)
            throw error
        }
        savedSession = session
        scheduleExpiry(for: session)
    }

    private func setDuration(_ duration: DurationChoice) throws {
        guard var session = savedSession else { return }
        guard try Self.readSleepDisabled() else {
            clearSavedSession()
            return
        }
        session.deadline = try makeDeadline(for: duration)
        try save(session)
        savedSession = session
        scheduleExpiry(for: session)
    }

    private func makeDeadline(for duration: DurationChoice?) throws -> Date? {
        guard let duration else { throw SleepManagerError.invalidRequest }
        switch duration {
        case .unlimited:
            return nil
        case .minutes(let minutes):
            guard minutes > 0, let seconds = duration.seconds else {
                throw SleepManagerError.invalidRequest
            }
            let deadline = Date().addingTimeInterval(TimeInterval(seconds))
            guard deadline.timeIntervalSince1970.isFinite else { throw SleepManagerError.invalidRequest }
            return deadline
        }
    }

    private func restoreSavedSession() throws {
        guard let session = savedSession else { return }
        if try Self.readSleepDisabled() != session.originalSleepDisabled {
            try Self.setSleepDisabled(session.originalSleepDisabled)
        }
        clearSavedSession()
    }

    private func clearSavedSession() {
        expiryTimer?.cancel()
        expiryTimer = nil
        reconnectTimer?.cancel()
        reconnectTimer = nil
        savedSession = nil
        do {
            if FileManager.default.fileExists(atPath: Self.stateURL.path) {
                try FileManager.default.removeItem(at: Self.stateURL)
            }
        } catch {
            NSLog("Clamsomnia helper could not remove its saved sleep session: %@", error.localizedDescription)
        }
    }

    private func scheduleExpiry(for session: SavedSleepSession) {
        expiryTimer?.cancel()
        guard let deadline = session.deadline else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + max(0, deadline.timeIntervalSinceNow))
        timer.setEventHandler { [weak self] in
            guard let self, self.savedSession?.deadline == deadline else { return }
            do {
                try self.restoreSavedSession()
            } catch {
                NSLog("Clamsomnia helper could not restore sleep settings at timer expiry: %@", error.localizedDescription)
                self.scheduleRestoreRetry()
            }
        }
        expiryTimer = timer
        timer.resume()
    }

    private func scheduleReconnectRecovery() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60)
        timer.setEventHandler { [weak self] in
            guard let self, self.clientCounts.isEmpty, self.savedSession != nil else { return }
            do {
                try self.restoreSavedSession()
            } catch {
                NSLog("Clamsomnia helper could not restore after its reconnect grace period: %@", error.localizedDescription)
                self.scheduleRestoreRetry()
            }
        }
        reconnectTimer = timer
        timer.resume()
    }

    private func scheduleStartupRecoveryRetry() {
        reconnectTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5)
        timer.setEventHandler { [weak self] in
            guard let self, self.clientCounts.isEmpty, self.savedSession != nil else { return }
            self.recoverOnStartup()
        }
        reconnectTimer = timer
        timer.resume()
    }

    private func scheduleRestoreRetry() {
        expiryTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5)
        timer.setEventHandler { [weak self] in
            guard let self, self.savedSession != nil else { return }
            do {
                try self.restoreSavedSession()
            } catch {
                NSLog("Clamsomnia helper will retry sleep restoration: %@", error.localizedDescription)
                self.scheduleRestoreRetry()
            }
        }
        expiryTimer = timer
        timer.resume()
    }

    private func save(_ session: SavedSleepSession) throws {
        let directory = Self.stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(session)
        try data.write(to: Self.stateURL, options: .atomic)
        guard chmod(Self.stateURL.path, 0o600) == 0 else { throw SleepManagerError.stateWriteFailed(errno) }
    }

    private static func currentBootTime() -> TimeInterval {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        let result = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &bootTime, &size, nil, 0)
        }
        guard result == 0 else { return 0 }
        return TimeInterval(bootTime.tv_sec) + TimeInterval(bootTime.tv_usec) / 1_000_000
    }

    private static func readSleepDisabled() throws -> Bool {
        let output = try runPMSet(["-g"])
        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line.split(whereSeparator: \.isWhitespace)
            if columns.count >= 2, columns[0] == "SleepDisabled" {
                return columns[1] == "1"
            }
        }
        throw SleepManagerError.sleepStateUnavailable
    }

    private static func setSleepDisabled(_ disabled: Bool) throws {
        _ = try runPMSet(["-a", "disablesleep", disabled ? "1" : "0"])
    }

    private static func runPMSet(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SleepManagerError.pmsetFailed(detail.isEmpty ? "pmset exited with status \(process.terminationStatus)." : detail)
        }
        return text
    }
}

private enum SleepManagerError: LocalizedError {
    case unauthorizedClient
    case invalidRequest
    case stateWriteFailed(Int32)
    case sleepStateUnavailable
    case pmsetFailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorizedClient:
            return "The caller is not an authorized Clamsomnia app process."
        case .invalidRequest:
            return "The helper received an invalid sleep-control request."
        case .stateWriteFailed(let code):
            return "The helper could not save its recovery state (errno \(code))."
        case .sleepStateUnavailable:
            return "pmset did not report the SleepDisabled setting."
        case .pmsetFailed(let detail):
            return "pmset failed: \(detail)"
        }
    }
}
