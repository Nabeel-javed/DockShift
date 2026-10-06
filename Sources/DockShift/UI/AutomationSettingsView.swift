import AppKit
import SwiftUI

/// Settings → Automation: rules that switch Docks, and the dockshift:// links.
struct AutomationSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProfileStore

    var body: some View {
        Form {
            Section {
                if settings.automation.rules.isEmpty {
                    Text("No rules yet. Add one to switch Docks when an app comes to the front, or at set times.")
                        .foregroundStyle(.secondary)
                }
                ForEach($settings.automation.rules) { $rule in
                    SwitchRuleRow(rule: $rule) {
                        settings.automation.rules.removeAll { $0.id == rule.id }
                    }
                }
                HStack {
                    Menu {
                        Button("When an App Is in Front…", action: addAppRule)
                        Button("At a Time…", action: addScheduleRule)
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .fixedSize()
                    Spacer()
                }
            } header: {
                Text("Switch Docks automatically")
            }

            Section {
                Toggle("Switch back when the app is no longer in front", isOn: $settings.automation.switchBackWhenAppLeaves)
            }

            Section {
                LinkRow(link: "dockshift://switch/" + (store.profiles.first?.name ?? "Work"), detail: "Use a Dock by name")
                LinkRow(link: "dockshift://use/custom", detail: "Use the Custom Dock")
                LinkRow(link: "dockshift://use/original", detail: "Use Apple's Dock")
                LinkRow(link: "dockshift://next", detail: "Next Dock (also /previous)")
            } header: {
                Text("Links")
            } footer: {
                Text("Open these from Raycast, Alfred, Stream Deck, Shortcuts (Open URL) or Terminal (`open`).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addAppRule() {
        let panel = NSOpenPanel()
        panel.message = "Choose the app that switches Docks when it comes to the front."
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        settings.automation.rules.append(SwitchRule(trigger: .app(bundleID: bundleID, name: name)))
    }

    private func addScheduleRule() {
        settings.automation.rules.append(SwitchRule(trigger: .schedule(hour: 9, minute: 0, weekdays: [2, 3, 4, 5, 6])))
    }
}

private struct SwitchRuleRow: View {
    @EnvironmentObject private var store: ProfileStore
    @Binding var rule: SwitchRule
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("", isOn: $rule.isEnabled).labelsHidden()
                trigger
                Spacer()
                Picker("Use", selection: $rule.profileID) {
                    Text("Choose a Dock").tag(UUID?.none)
                    ForEach(store.profiles) { profile in
                        Text("\(profile.name) (\(profile.kind.title))").tag(UUID?.some(profile.id))
                    }
                }
                .fixedSize()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete rule")
            }
            if case .schedule(_, _, let weekdays) = rule.trigger {
                HStack(spacing: 4) {
                    DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
                        .fixedSize()
                    Spacer()
                    ForEach(orderedWeekdays, id: \.self) { weekday in
                        let on = weekdays.contains(weekday)
                        Button(Calendar.current.veryShortWeekdaySymbols[weekday - 1]) { toggle(weekday) }
                            .buttonStyle(.borderless)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                }
            }
        }
        .opacity(rule.isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private var trigger: some View {
        switch rule.trigger {
        case .app(let bundleID, let name):
            HStack(spacing: 6) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Text("When \(name) is in front")
            }
        case .schedule:
            Label("At a time", systemImage: "clock")
        }
    }

    /// Weekday numbers (1 = Sunday) starting from the user's first day of the week.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                guard case .schedule(let hour, let minute, _) = rule.trigger else { return Date() }
                return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                guard case .schedule(_, _, let weekdays) = rule.trigger else { return }
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.trigger = .schedule(hour: parts.hour ?? 0, minute: parts.minute ?? 0, weekdays: weekdays)
            }
        )
    }

    private func toggle(_ weekday: Int) {
        guard case .schedule(let hour, let minute, var weekdays) = rule.trigger else { return }
        if weekdays.contains(weekday) { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
        rule.trigger = .schedule(hour: hour, minute: minute, weekdays: weekdays)
    }
}

private struct LinkRow: View {
    let link: String
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(link).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.replacingOccurrences(of: " ", with: "%20"), forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy link")
        }
    }
}
