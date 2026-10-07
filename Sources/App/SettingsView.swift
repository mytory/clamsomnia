import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: HelperSleepController
    let firstRun: Bool
    let finishSetup: () -> Void
    let showError: (Error) -> Void

    @AppStorage(AppPreferences.activateOnLaunchKey) private var activateOnLaunch = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginApprovalRequired = SMAppService.mainApp.status == .requiresApproval
    @State private var minutes: Int
    @State private var unlimited: Bool
    @State private var saving = false
    @State private var durationSaveTask: Task<Void, Never>?

    init(
        controller: HelperSleepController,
        firstRun: Bool,
        finishSetup: @escaping () -> Void,
        showError: @escaping (Error) -> Void
    ) {
        self.controller = controller
        self.firstRun = firstRun
        self.finishSetup = finishSetup
        self.showError = showError
        switch controller.configuredDuration {
        case .minutes(let value):
            _minutes = State(initialValue: value)
            _unlimited = State(initialValue: false)
        case .unlimited:
            _minutes = State(initialValue: 300)
            _unlimited = State(initialValue: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(firstRun ? "방지 시간 설정" : "설정")
                    .font(.title2.weight(.semibold))
                Text(firstRun
                     ? "잠자기 방지를 켰을 때 자동으로 해제될 때까지의 시간을 선택하세요."
                     : "기본 방지 시간과 앱 실행 동작을 설정합니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox("잠자기 방지 시간") {
                DurationSelector(minutes: $minutes, unlimited: $unlimited)
                    .padding(.vertical, 4)
                    .onChange(of: minutes) { _, newValue in
                        guard !firstRun, !unlimited, newValue > 0 else { return }
                        scheduleDurationSave(.minutes(newValue))
                    }
                    .onChange(of: unlimited) { _, isUnlimited in
                        guard !firstRun else { return }
                        durationSaveTask?.cancel()
                        if isUnlimited {
                            saveDuration(.unlimited)
                        } else if minutes > 0 {
                            scheduleDurationSave(.minutes(minutes))
                        }
                    }
            }

            if !firstRun {
                GroupBox("앱 동작") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("로그인할 때 실행", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, enabled in
                                setLaunchAtLogin(enabled)
                            }
                        if loginApprovalRequired {
                            Text("이 옵션을 켜려면 시스템 설정 → 일반 → 로그인 항목에서 Clamsomnia를 허용하세요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Toggle("Clamsomnia를 열 때 잠자기 방지 켜기", isOn: $activateOnLaunch)
                    }
                    .padding(.vertical, 4)
                }
            }

            if firstRun {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("계속") {
                        finishInitialSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || (!unlimited && minutes < 1))
                }
            } else {
                Text("방지 시간 변경은 자동 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(22)
        .frame(width: 420, height: firstRun ? 310 : 420)
        .onAppear(perform: refreshLaunchAtLoginState)
    }

    private func finishInitialSetup() {
        saving = true
        let choice: DurationChoice = unlimited ? .unlimited : .minutes(max(1, minutes))
        Task {
            do {
                try await controller.setDuration(choice)
                saving = false
                if firstRun { finishSetup() }
            } catch {
                saving = false
                showError(error)
            }
        }
    }

    private func scheduleDurationSave(_ choice: DurationChoice) {
        durationSaveTask?.cancel()
        durationSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            saveDuration(choice)
        }
    }

    private func saveDuration(_ choice: DurationChoice) {
        Task { @MainActor in
            do {
                try await controller.setDuration(choice)
            } catch {
                showError(error)
            }
        }
    }

    private func refreshLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        loginApprovalRequired = status == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginState()
        } catch {
            refreshLaunchAtLoginState()
            showError(error)
        }
    }
}
