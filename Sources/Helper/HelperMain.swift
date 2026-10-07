import Darwin
import Foundation
import Security
import SystemConfiguration

private let machServiceName = "com.mytory.Clamsomnia.helper"
private let allowedBundleIdentifier = "com.mytory.Clamsomnia"
private let allowedExecutablePath = "/Applications/Clamsomnia.app/Contents/MacOS/Clamsomnia"

@objc final class SleepHelperExport: NSObject, SleepHelperXPCProtocol {
    private let manager: SleepManager
    private let clientPID: pid_t

    init(manager: SleepManager, clientPID: pid_t) {
        self.manager = manager
        self.clientPID = clientPID
    }

    func perform(_ request: NSData, withReply reply: @escaping (NSData?, NSString?) -> Void) {
        manager.perform(request as Data, from: clientPID) { data, message in
            reply(data as NSData?, message as NSString?)
        }
    }
}

private final class SleepHelperListener: NSObject, NSXPCListenerDelegate {
    private let manager: SleepManager

    init(manager: SleepManager) {
        self.manager = manager
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        guard Self.isAuthorizedClient(pid: pid) else {
            NSLog("Clamsomnia helper rejected unauthorized XPC client pid %d", pid)
            return false
        }

        manager.connectClient(pid: pid)
        connection.exportedInterface = NSXPCInterface(with: SleepHelperXPCProtocol.self)
        connection.exportedObject = SleepHelperExport(manager: manager, clientPID: pid)
        connection.invalidationHandler = { [weak manager] in
            manager?.disconnectClient(pid: pid)
        }
        connection.resume()
        return true
    }

    private static func isAuthorizedClient(pid: pid_t) -> Bool {
        guard pid > 1,
              belongsToConsoleUser(pid: pid),
              hasExpectedExecutablePath(pid: pid),
              hasExpectedCodeSignature(pid: pid) else { return false }
        return true
    }

    private static func belongsToConsoleUser(pid: pid_t) -> Bool {
        var consoleUID: uid_t = 0
        guard SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil) != nil else { return false }
        var processInfo = proc_bsdinfo()
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &processInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
        return count == MemoryLayout<proc_bsdinfo>.size && processInfo.pbi_uid == consoleUID
    }

    private static func hasExpectedExecutablePath(pid: pid_t) -> Bool {
        var pathBuffer = [CChar](repeating: 0, count: 4_096)
        let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard length > 0,
              String(cString: pathBuffer) == allowedExecutablePath else { return false }

        var path = ""
        for component in URL(fileURLWithPath: allowedExecutablePath).pathComponents {
            if component == "/" {
                path = "/"
                continue
            }
            path = path == "/" ? "/\(component)" : "\(path)/\(component)"
            var fileInfo = stat()
            // macOS keeps /Applications root-owned but group-writable; the installed app subtree stays protected.
            let writableBits = path == "/Applications" ? mode_t(S_IWOTH) : mode_t(S_IWGRP | S_IWOTH)
            guard lstat(path, &fileInfo) == 0,
                  fileInfo.st_uid == 0,
                  fileInfo.st_mode & writableBits == 0 else { return false }
        }
        return true
    }

    private static func hasExpectedCodeSignature(pid: pid_t) -> Bool {
        let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
        var guestCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guestCode) == errSecSuccess,
              let guestCode else { return false }

        let requirementText = "identifier \"\(allowedBundleIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement,
              SecCodeCheckValidity(guestCode, SecCSFlags(), requirement) == errSecSuccess else { return false }
        return true
    }
}

@main
enum HelperMain {
    static func main() {
        if CommandLine.arguments.contains("--restore") {
            guard geteuid() == 0 else {
                fputs("Clamsomnia helper --restore must run as root.\n", stderr)
                exit(EXIT_FAILURE)
            }
            do {
                try SleepManager.restoreFromDisk()
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Clamsomnia helper could not restore sleep settings: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        let manager = SleepManager()
        let delegate = SleepHelperListener(manager: manager)
        let listener = NSXPCListener(machServiceName: machServiceName)
        listener.delegate = delegate

        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let termSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        let interruptSignal = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let stop: () -> Void = {
            manager.shutdownAndRestore()
            listener.invalidate()
            exit(EXIT_SUCCESS)
        }
        termSignal.setEventHandler(handler: stop)
        interruptSignal.setEventHandler(handler: stop)
        termSignal.resume()
        interruptSignal.resume()

        listener.resume()
        RunLoop.main.run()
    }
}
