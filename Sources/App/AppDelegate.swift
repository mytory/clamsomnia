import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controller: HelperSleepController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var refreshTimer: Timer?
    private var controllerSubscription: AnyCancellable?
    private var contextMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = HelperSleepController(configuredDuration: .minutes(300))
        makeStatusItem()
        observeController()

        Task {
            do {
                try await controller.refresh()
            } catch {
                showActionError(error)
            }
            updateStatusIcon()

            if !controller.hasConfiguredDuration {
                showSettings(firstRun: true)
            } else if UserDefaults.standard.bool(forKey: AppPreferences.activateOnLaunchKey) {
                do {
                    try await controller.setEnabled(true)
                } catch {
                    showActionError(error)
                }
            }
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                try? await self.controller.refresh()
                self.updateStatusIcon()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === settingsWindow, !controller.hasConfiguredDuration else { return true }
        return false
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = CatIcon.image(isAwake: false)
        button.image?.isTemplate = true
        button.toolTip = "Clamsomnia 메뉴"
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    }

    private func observeController() {
        controllerSubscription = controller.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.updateStatusIcon() }
        }
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleSleep()
            return
        }
        if event.type == .rightMouseUp {
            showStatusMenu(button: sender)
        } else {
            toggleSleep()
        }
    }

    private func toggleSleep() {
        guard controller.hasConfiguredDuration else {
            showSettings(firstRun: true)
            return
        }
        Task {
            do {
                try await controller.toggle()
            } catch {
                showActionError(error)
            }
            updateStatusIcon()
        }
    }

    private func showStatusMenu(button: NSStatusBarButton) {
        guard controller.hasConfiguredDuration else {
            showSettings(firstRun: true)
            return
        }

        let menu = NSMenu(title: "Clamsomnia")
        menu.autoenablesItems = false
        menu.addItem(infoItem("Clamsomnia"))
        menu.addItem(infoItem(controller.status.isEnabled ? "잠자기 방지 중" : "잠자기 허용 중"))
        menu.addItem(infoItem("방지 시간: \(durationLabel(controller.configuredDuration))"))
        menu.addItem(infoItem("남은 시간: \(remainingLabel)"))
        menu.addItem(infoItem("복구 시한: \(deadlineLabel)"))
        if controller.status.ownership == .external && controller.status.isEnabled {
            menu.addItem(infoItem("다른 앱이나 도구에서 이미 잠자기 방지를 켰습니다."))
        }
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: controller.status.isEnabled ? "잠자기 허용" : "잠자기 방지 켜기",
            action: #selector(toggleFromMenu(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let sleepItem = NSMenuItem(
            title: "방지 해제 후 잠자기",
            action: #selector(disableThenSleepFromMenu(_:)),
            keyEquivalent: ""
        )
        sleepItem.target = self
        menu.addItem(sleepItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "설정…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "종료", action: #selector(quitFromMenu(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        contextMenu = menu
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 10), in: button)
        contextMenu = nil
    }

    @objc private func toggleFromMenu(_ sender: NSMenuItem) {
        toggleSleep()
    }

    @objc private func disableThenSleepFromMenu(_ sender: NSMenuItem) {
        Task {
            do {
                try await controller.sleepNowAfterDisabling()
            } catch {
                showActionError(error)
            }
        }
    }

    @objc private func openSettingsFromMenu(_ sender: NSMenuItem) {
        showSettings(firstRun: false)
    }

    @objc private func quitFromMenu(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = true
        return item
    }

    private var remainingLabel: String {
        guard controller.status.isEnabled else { return "비활성" }
        guard let deadline = controller.status.deadline else {
            return controller.status.ownership == .external ? "남은 시간 확인 불가" : "무제한"
        }
        let seconds = max(0, Int(deadline.timeIntervalSinceNow))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분" }
        return "\(max(1, minutes))분"
    }

    private var deadlineLabel: String {
        guard controller.status.isEnabled else { return "비활성" }
        if let deadline = controller.status.deadline {
            return deadline.formatted(date: .abbreviated, time: .shortened)
        }
        return controller.status.ownership == .external ? "정해진 시한 없음" : "자동 복구 안 함"
    }

    private func showSettings(firstRun: Bool) {
        if let settingsWindow {
            if !firstRun || !controller.hasConfiguredDuration {
                settingsWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        let content = SettingsView(
            controller: controller,
            firstRun: firstRun,
            finishSetup: { [weak self] in
                self?.settingsWindow?.close()
                self?.settingsWindow = nil
            },
            showError: { [weak self] in self?.showActionError($0) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: firstRun ? 550 : 660),
            styleMask: firstRun ? [.titled] : [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = firstRun ? "Clamsomnia 시작" : "Clamsomnia 설정"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: content)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let isAwake = controller?.status.isEnabled ?? false
        let image = CatIcon.image(isAwake: isAwake)
        image.isTemplate = true
        button.image = image
        button.toolTip = isAwake ? "Clamsomnia — 잠자기 방지 중" : "Clamsomnia — 잠자기 허용 중"
    }

    private func showActionError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Clamsomnia에서 잠자기 설정을 변경하지 못했습니다"
        alert.informativeText = actionErrorDescription(error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    private func actionErrorDescription(_ error: Error) -> String {
        guard let error = error as? SleepControlError else { return error.localizedDescription }
        switch error {
        case .helperUnavailable:
            return "잠자기 제어 도우미에 연결하지 못했습니다. 도우미 설치 상태를 확인한 뒤 다시 시도해 주세요."
        case .operationFailed:
            return "시스템 잠자기 설정을 변경하지 못했습니다. 다시 시도해 주세요."
        case .invalidResponse:
            return "도우미에서 올바른 응답을 받지 못했습니다. 다시 시도해 주세요."
        }
    }
}

enum AppPreferences {
    static let activateOnLaunchKey = "activateOnLaunch"
}
