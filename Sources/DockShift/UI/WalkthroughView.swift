import SwiftUI

/// Three-step first launch: pick a Dock setup, save a first Dock, learn
/// where things are.
struct WalkthroughView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var settings: AppSettings
    @State private var step = 0
    let onFinished: (DockProfile?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: 36, height: 4)
                }
            }
            .padding(.top, 20)

            Group {
                switch step {
                case 0: setupStep
                case 1: saveStep
                default: doneStep
                }
            }
            .frame(maxWidth: 560, maxHeight: .infinity)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Step 1

    private var setupStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Welcome to DockShift")
                .font(.largeTitle.weight(.semibold))
            Text("Which Dock do you want to use? You can change this any time from the menu bar or Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                SetupCard(title: "Original macOS Dock",
                          detail: "Keep Apple's Dock and switch between saved layouts of it.",
                          selected: !settings.dockSetup.usesCustomDock) {
                    settings.dockSetup = .macOSOnly
                }
                SetupCard(title: "Custom Dock",
                          detail: "Replace Apple's Dock with DockShift's Dock: your apps, folders, files, links and widgets.",
                          selected: settings.dockSetup.usesCustomDock) {
                    settings.dockSetup = .customMain
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Continue") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: Step 2

    private var saveStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "dock.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Save your first Dock")
                .font(.title.weight(.semibold))
            Text(settings.dockSetup == .macOSOnly
                 ? "Keep the apps already in your Dock, or start with an empty layout."
                 : "Your current macOS Dock is saved as a profile, and a Custom Dock with the same apps plus a few widgets is created for you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Start Empty") {
                    finish(store.createEmpty(name: "New Dock"))
                }
                Button("Create from Current Dock") {
                    finish(store.createFromCurrentDock(name: "Everyday"))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
            HStack {
                Button("Back") { step = 0 }
                Spacer()
            }
            .padding(.bottom, 20)
        }
    }

    private func finish(_ first: DockProfile) {
        if settings.dockSetup.showsCustomDock, store.profiles(of: .customDock).isEmpty {
            var custom = store.createFromCurrentDock(name: "Custom Dock", kind: .customDock, extraItems: [
                .spacer(.regular),
                .widget(WidgetInstance(type: .clock)),
                .widget(WidgetInstance(type: .calendar, variant: "nextEvent")),
            ])
            custom.color = .teal
            store.update(custom)
        }
        step = 2
        createdProfile = first
    }

    @State private var createdProfile: DockProfile?

    // MARK: Step 3

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("You're set")
                .font(.title.weight(.semibold))
                .frame(maxWidth: .infinity)
            tip("menubar.rectangle", "Switch Docks from the menu bar",
                "Click the DockShift icon and pick a saved Dock. Assign shortcuts in Settings → Shortcuts.")
            tip("square.grid.2x2", "Add widgets to your Custom Dock",
                "In Manage Docks, select a Custom Dock profile and use Add → Widget…. Right-click a widget to configure it.")
            tip("moon.fill", "Let Focus switch for you",
                "In System Settings → Focus, add the DockShift “Switch Dock” filter to a Focus.")
            tip("lock.shield", "Permissions are optional",
                "Calendar, Reminders, Automation, Accessibility and Screen Recording are only requested by the features that use them.")
            Spacer()
            HStack {
                Spacer()
                Button("Open Manage Docks") { onFinished(createdProfile) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 20)
        }
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetupCard: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
