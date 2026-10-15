import Foundation

@main
enum PreventionOptionsTests {
    @MainActor
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }

        let options = PreventionOptions(batteryThreshold: 20, preventAutoLock: true)
        check(options.shouldRestore(batteryPercent: 20, onBattery: true), "Restore at threshold")
        check(options.shouldRestore(batteryPercent: 0, onBattery: true), "Restore below threshold")
        check(!options.shouldRestore(batteryPercent: 21, onBattery: true), "Keep session above threshold")
        check(!options.shouldRestore(batteryPercent: 10, onBattery: false), "Keep session on AC power")
        check(!options.shouldRestore(batteryPercent: nil, onBattery: true), "Ignore unavailable battery")
        check(!PreventionOptions.defaults.shouldRestore(batteryPercent: 0, onBattery: true), "Opt in only")
        check(!PreventionOptions.defaults.preventAutoLock, "Auto lock prevention defaults off")
        for value in [1, 20, 100] {
            check(PreventionOptions(batteryThreshold: value).isValid, "Valid threshold")
        }
        for value in [-1, 0, 101] {
            check(!PreventionOptions(batteryThreshold: value).isValid, "Reject invalid threshold")
        }
        let encoded = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(PreventionOptions.self, from: encoded)
        check(decoded == options, "Options survive persistence")
        let legacy = try JSONDecoder().decode(SleepHelperRequest.self, from: Data("{\"operation\":\"status\"}".utf8))
        check(legacy.options == nil, "Accept old requests without options")
        let request = SleepHelperRequest(operation: .setOptions, options: options)
        let requestData = try JSONEncoder().encode(request)
        let decodedRequest = try JSONDecoder().decode(SleepHelperRequest.self, from: requestData)
        check(decodedRequest.options == options, "Options survive XPC serialization")

        let suite = "Clamsomnia.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(HelperSleepController(defaults: defaults).preventionOptions == .defaults, "Fresh install defaults")
        defaults.set(encoded, forKey: "Clamsomnia.preventionOptions")
        check(HelperSleepController(defaults: defaults).preventionOptions == options, "Load saved options")
        defaults.set(try JSONEncoder().encode(PreventionOptions(batteryThreshold: 101)), forKey: "Clamsomnia.preventionOptions")
        check(HelperSleepController(defaults: defaults).preventionOptions == .defaults, "Ignore invalid saved threshold")
        print("Passed \(checks) prevention option checks")
    }
}
