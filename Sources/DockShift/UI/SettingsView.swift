import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProfileStore
    @State private var backupMessage: String?
    @State private var screenCaptureGranted = DockTransition.hasScreenCapturePermission

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show active Dock name in menu bar", isOn: $settings.showProfileNameInMenuBar)
                Toggle("Automatically save Dock changes", isOn: $settings.autoSaveDockChanges)
                Text("Changes you make directly in Apple's Dock are synced to the active profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Switching") {
                Toggle("Smooth Dock switching", isOn: $settings.smoothSwitching)
                HStack {
                    if screenCaptureGranted {
                        Label("Screen Recording access granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Needs Screen Recording access", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access…") {
                            DockTransition.requestScreenCapturePermission()
                            screenCaptureGranted = DockTransition.hasScreenCapturePermission
                            openScreenRecordingSettings()
                        }
                    }
                }
                .font(.caption)
                Text("Hides the flicker while the Dock restarts by freezing a snapshot of it. Without Screen Recording access, switching still works but is not smooth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Saved Docks") {
                HStack {
                    Button("Back Up…", action: backUp)
                    Button("Restore…", action: restore)
                    Spacer()
                    Text("\(store.profiles.count) saved")
                        .foregroundStyle(.secondary)
                }
                Text("Restore adds copies of the backed-up Docks. Existing profiles are not replaced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let backupMessage {
                    Text(backupMessage).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenCaptureGranted = DockTransition.hasScreenCapturePermission
        }
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func backUp() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DockShift Backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportBackup(to: url)
            backupMessage = "Backed up \(store.profiles.count) Docks."
        } catch {
            backupMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try store.importBackup(from: url)
            backupMessage = "Restored \(count) Docks as copies."
        } catch {
            backupMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}

private struct ShortcutsSettingsView: View {
    @EnvironmentObject private var store: ProfileStore

    var body: some View {
        Form {
            Section {
                if store.profiles.isEmpty {
                    Text("Save a Dock first, then assign it a shortcut here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.profiles) { profile in
                        HStack {
                            Circle()
                                .fill(profile.color.color)
                                .frame(width: 9, height: 9)
                            Text(profile.name)
                            Spacer()
                            ShortcutRecorder(combo: binding(for: profile.id))
                        }
                    }
                }
            } header: {
                Text("Switch to a Dock from anywhere")
            } footer: {
                Text("Shortcuts work system-wide. Press Escape while recording to cancel.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for id: UUID) -> Binding<KeyCombo?> {
        Binding(
            get: { store.profile(id: id)?.shortcut },
            set: { newValue in
                guard var profile = store.profile(id: id) else { return }
                profile.shortcut = newValue
                store.update(profile)
            }
        )
    }
}

private struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 48, weight: .light))
            Text("DockShift")
                .font(.title.bold())
            Text(version)
                .foregroundStyle(.secondary)
            Text("Save and switch your macOS Dock layouts.")
                .padding(.top, 4)
            Text("Open source under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
