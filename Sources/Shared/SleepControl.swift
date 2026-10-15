import Combine
import Foundation

struct PreventionOptions: Codable, Equatable, Sendable {
    var batteryThreshold: Int?
    var preventAutoLock = false

    static let defaults = PreventionOptions()

    var isValid: Bool {
        batteryThreshold.map { (1...100).contains($0) } ?? true
    }

    func shouldRestore(batteryPercent: Int?, onBattery: Bool) -> Bool {
        guard onBattery, let batteryThreshold, let batteryPercent else { return false }
        return batteryPercent <= batteryThreshold
    }
}

enum SleepOwnership: String, Codable, Equatable, Sendable {
    case app
    case external
    case none
}

struct SleepStatus: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var ownership: SleepOwnership
    var deadline: Date?

    var remaining: TimeInterval? {
        guard let deadline else { return nil }
        return max(0, deadline.timeIntervalSinceNow)
    }

    static let disabled = SleepStatus(isEnabled: false, ownership: .none, deadline: nil)
}

enum DurationChoice: Codable, Equatable, Sendable {
    case minutes(Int)
    case unlimited

    var seconds: Int64? {
        switch self {
        case .minutes(let minutes):
            guard minutes > 0 else { return nil }
            let (seconds, overflow) = Int64(minutes).multipliedReportingOverflow(by: 60)
            return overflow ? nil : seconds
        case .unlimited:
            return nil
        }
    }
}

@MainActor
protocol SleepControlling: ObservableObject {
    var status: SleepStatus { get }
    var configuredDuration: DurationChoice { get }
    var hasConfiguredDuration: Bool { get }

    func refresh() async throws
    func toggle() async throws
    func setEnabled(_ enabled: Bool) async throws
    func setDuration(_ duration: DurationChoice) async throws
    func sleepNowAfterDisabling() async throws
}

enum SleepControlError: LocalizedError {
    case helperUnavailable(String)
    case operationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .helperUnavailable(let message):
            return "The sleep-control helper is unavailable: \(message)"
        case .operationFailed(let message):
            return message
        case .invalidResponse:
            return "The sleep-control helper returned an invalid response."
        }
    }
}

@MainActor
final class HelperSleepController: ObservableObject, SleepControlling {
    @Published private(set) var status = SleepStatus.disabled
    @Published private(set) var configuredDuration: DurationChoice
    @Published private(set) var hasConfiguredDuration: Bool
    @Published private(set) var preventionOptions: PreventionOptions

    private static let helperMachService = "com.mytory.Clamsomnia.helper"
    private static let durationDefaultsKey = "Clamsomnia.configuredDuration"
    private static let optionsDefaultsKey = "Clamsomnia.preventionOptions"

    private var connection: NSXPCConnection?
    private let defaults: UserDefaults

    init(configuredDuration defaultDuration: DurationChoice = .minutes(300), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preventionOptions = defaults.data(forKey: Self.optionsDefaultsKey)
            .flatMap { try? JSONDecoder().decode(PreventionOptions.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil } ?? .defaults
        if let data = defaults.data(forKey: Self.durationDefaultsKey),
           let saved = try? JSONDecoder().decode(DurationChoice.self, from: data) {
            configuredDuration = saved
            hasConfiguredDuration = true
        } else {
            configuredDuration = defaultDuration
            hasConfiguredDuration = false
        }
    }

    func refresh() async throws {
        try await send(.status)
    }

    func toggle() async throws {
        try await refresh()
        try await setEnabled(!status.isEnabled)
    }

    func setEnabled(_ enabled: Bool) async throws {
        try await send(.setEnabled, enabled: enabled, duration: configuredDuration)
    }

    func setDuration(_ duration: DurationChoice) async throws {
        if status.isEnabled && status.ownership == .app {
            try await send(.setDuration, duration: duration)
        }
        configuredDuration = duration
        hasConfiguredDuration = true
        if let data = try? JSONEncoder().encode(duration) {
            defaults.set(data, forKey: Self.durationDefaultsKey)
        }
    }

    func sleepNowAfterDisabling() async throws {
        try await send(.sleepNow, duration: configuredDuration)
    }

    func setPreventionOptions(_ options: PreventionOptions) async throws {
        guard options.isValid else { throw SleepControlError.invalidResponse }
        try await send(.setOptions, options: options)
        preventionOptions = options
        defaults.set(try JSONEncoder().encode(options), forKey: Self.optionsDefaultsKey)
    }

    private func send(
        _ operation: SleepHelperOperation,
        enabled: Bool? = nil,
        duration: DurationChoice? = nil,
        options: PreventionOptions? = nil
    ) async throws {
        let request = SleepHelperRequest(operation: operation, enabled: enabled, duration: duration,
                                         options: options ?? preventionOptions)
        let requestData = try JSONEncoder().encode(request)
        let activeConnection = connection ?? makeConnection()

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            let proxy = activeConnection.remoteObjectProxyWithErrorHandler { [weak self] error in
                Task { @MainActor in
                    if self?.connection === activeConnection {
                        self?.connection = nil
                    }
                }
                continuation.resume(throwing: SleepControlError.helperUnavailable(error.localizedDescription))
            } as! SleepHelperXPCProtocol

            proxy.perform(requestData as NSData) { data, message in
                if let message {
                    continuation.resume(throwing: SleepControlError.operationFailed(message as String))
                } else if let data {
                    continuation.resume(returning: data as Data)
                } else {
                    continuation.resume(throwing: SleepControlError.invalidResponse)
                }
            }
        }

        guard let response = try? JSONDecoder().decode(SleepHelperResponse.self, from: responseData) else {
            throw SleepControlError.invalidResponse
        }
        status = response.status
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: Self.helperMachService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperXPCProtocol.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            Task { @MainActor in
                guard let connection, self?.connection === connection else { return }
                self?.connection = nil
            }
        }
        self.connection = connection
        connection.resume()
        return connection
    }
}

enum SleepHelperOperation: String, Codable {
    case status
    case setEnabled
    case setDuration
    case sleepNow
    case setOptions
}

struct SleepHelperRequest: Codable {
    var operation: SleepHelperOperation
    var enabled: Bool?
    var duration: DurationChoice?
    var options: PreventionOptions? = nil
}

struct SleepHelperResponse: Codable {
    var status: SleepStatus
}

@objc protocol SleepHelperXPCProtocol {
    func perform(_ request: NSData, withReply reply: @escaping (NSData?, NSString?) -> Void)
}
