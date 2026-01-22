import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var manager: UsageManager
    var inline: Bool = false

    @AppStorage("refreshInterval") private var refreshInterval: Int = Constants.RefreshInterval.defaultValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @State private var launchAtLogin: Bool = false

    var body: some View {
        if inline {
            inlineContent
        } else {
            windowContent
        }
    }

    // MARK: - Inline Content (for MenuBarExtra popup)

    private var inlineContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Refresh Interval")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $refreshInterval) {
                ForEach(Constants.RefreshInterval.options, id: \.value) { option in
                    Text(option.shortLabel).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: refreshInterval) { _, newValue in
                manager.updateRefreshInterval(newValue)
            }

            Divider()

            Toggle("Alert when usage > 90%", isOn: $notificationsEnabled)
                .toggleStyle(.checkbox)

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(enabled: newValue)
                }

            Divider()

            Text("⌘⌥U Refresh")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Window Content (for standalone Settings window)

    private var windowContent: some View {
        Form {
            Section("Refresh") {
                Picker("Interval:", selection: $refreshInterval) {
                    ForEach(Constants.RefreshInterval.options, id: \.value) { option in
                        Text(option.longLabel).tag(option.value)
                    }
                }
                .onChange(of: refreshInterval) { _, newValue in
                    manager.updateRefreshInterval(newValue)
                }
            }

            Section("Notifications") {
                Toggle("Alert when usage exceeds 90%", isOn: $notificationsEnabled)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
            }

            Section("About") {
                LabeledContent("Shortcut", value: "⌘⌥U Refresh")
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 280)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Helper

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently handle login item registration failure
        }
    }
}
