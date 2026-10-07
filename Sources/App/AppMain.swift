import AppKit
import Darwin
import ServiceManagement

@main
enum ClamsomniaMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--unregister-login") {
            do {
                switch SMAppService.mainApp.status {
                case .enabled, .requiresApproval:
                    try SMAppService.mainApp.unregister()
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    break
                }
                return
            } catch {
                fputs("로그인 항목에서 Clamsomnia를 해제하지 못했습니다: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
