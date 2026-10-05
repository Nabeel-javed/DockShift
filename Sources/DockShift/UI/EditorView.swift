import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "Manage Docks" window: profiles in the sidebar, the selected layout on the right.
struct EditorView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var selection: UUID?

    var body: some View {
        Group {
            if store.profiles.isEmpty {
                FirstRunView { created in selection = created.id }
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    if let id = selection, let profile = store.profile(id: id) {
                        ProfileDetailView(profile: profile)
                            .id(id)
                    } else {
                        Text("Select a Dock")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            if selection == nil {
                selection = store.activeProfileID ?? store.profiles.first?.id
            }
        }
        .onChange(of: store.profiles.map(\.id)) { ids in
            if let current = selection, !ids.contains(current) {
                selection = ids.first
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.profiles) { profile in
                    ProfileRow(profile: profile, isActive: profile.id == store.activeProfileID)
                        .tag(profile.id)
                }
                .onMove { source, destination in
                    store.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Menu {
                    Button("Create from Current Dock") {
                        selection = store.createFromCurrentDock(name: "Dock \(store.profiles.count + 1)").id
                    }
                    Button("Start Empty") {
                        selection = store.createEmpty(name: "New Dock").id
                    }
                } label: {
                    Label("New profile", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 320)
    }
}

private struct ProfileRow: View {
    let profile: DockProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(profile.color.color)
                .frame(width: 9, height: 9)
            Text(profile.name)
                .lineLimit(1)
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .help("Currently applied to your Dock")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - First run

private struct FirstRunView: View {
    @EnvironmentObject private var store: ProfileStore
    let onCreated: (DockProfile) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Save your first Dock")
                .font(.title2.bold())
            Text("Keep the apps already in your Dock, or start with an empty layout.\nYou can switch between saved Docks from the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Start Empty") {
                    onCreated(store.createEmpty(name: "New Dock"))
                }
                Button("Create from Current Dock") {
                    onCreated(store.createFromCurrentDock(name: "Everyday"))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail

private struct EditorItem: Identifiable {
    let id = UUID()
    var item: DockItem
}

private struct ProfileDetailView: View {
    @EnvironmentObject private var store: ProfileStore

    let profile: DockProfile
    @State private var draft: DockProfile
    @State private var items: [EditorItem]
    @State private var selectedItems = Set<UUID>()
    @State private var confirmDelete = false
    @State private var confirmReplace = false

    init(profile: DockProfile) {
        self.profile = profile
        _draft = State(initialValue: profile)
        _items = State(initialValue: profile.items.map { EditorItem(item: $0) })
    }

    private var saved: DockProfile { store.profile(id: profile.id) ?? profile }
    private var isActive: Bool { store.activeProfileID == profile.id }

    private var editedProfile: DockProfile {
        var result = draft
        result.items = items.map(\.item)
        return result
    }

    private var isDirty: Bool { editedProfile != saved }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            itemList
            Divider()
            footer
        }
        .confirmationDialog("Delete “\(saved.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.delete(profile.id) }
        } message: {
            Text("This removes the saved layout. Your Dock itself is not changed.")
        }
        .confirmationDialog("Replace with the current Dock?", isPresented: $confirmReplace) {
            Button("Replace") {
                store.replaceWithCurrentDock(profile.id)
                reloadFromStore()
            }
        } message: {
            Text("The saved items in “\(saved.name)” will be replaced with the apps and spacers pinned to your Dock right now.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(ProfileColor.allCases) { color in
                    Button {
                        draft.color = color
                    } label: {
                        Label(color.title, systemImage: draft.color == color ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                Circle()
                    .fill(draft.color.color)
                    .frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Profile color")

            TextField("Dock name", text: $draft.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .onSubmit(save)

            Spacer()

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            Menu("Profile actions") {
                Button("Replace with Current Dock…") { confirmReplace = true }
                Button("Duplicate") { store.duplicate(profile.id) }
                Divider()
                Button("Delete…", role: .destructive) { confirmDelete = true }
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var itemList: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Text("No apps yet")
                        .font(.headline)
                    Text("Use Add to pin apps and spacers to this Dock.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedItems) {
                    ForEach(items) { entry in
                        DockItemRow(item: entry.item)
                            .tag(entry.id)
                    }
                    .onMove { source, destination in
                        items.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                    }
                }
                .onDeleteCommand(perform: removeSelected)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Apps…", action: pickApps)
                Divider()
                Button(SpacerSize.small.title) { items.append(EditorItem(item: .spacer(.small))) }
                Button(SpacerSize.regular.title) { items.append(EditorItem(item: .spacer(.regular))) }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .fixedSize()

            Button("Remove", action: removeSelected)
                .disabled(selectedItems.isEmpty)

            Spacer()

            Text("\(editedProfile.appCount) apps")
                .foregroundStyle(.secondary)
                .font(.callout)

            Button("Save Changes", action: save)
                .disabled(!isDirty)

            Button(isActive ? "Apply Changes" : "Use this profile") {
                save()
                store.apply(profile.id)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isActive && !isDirty && saved.items == DockBridge.currentItems())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func save() {
        guard isDirty else { return }
        store.update(editedProfile)
    }

    private func reloadFromStore() {
        draft = saved
        items = saved.items.map { EditorItem(item: $0) }
        selectedItems.removeAll()
    }

    private func removeSelected() {
        items.removeAll { selectedItems.contains($0.id) }
        selectedItems.removeAll()
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps to pin"
        panel.message = "Select one or more applications."
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            items.append(EditorItem(item: .app(AppReference(url: url))))
        }
    }
}

private struct DockItemRow: View {
    let item: DockItem

    var body: some View {
        switch item {
        case .app(let app):
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.label)
                    Text(app.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !app.isInstalled {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("This app is not installed at the saved path.")
                }
            }
            .padding(.vertical, 2)
        case .spacer(let size):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .foregroundStyle(.secondary)
                    .frame(width: size == .small ? 14 : 28, height: 28)
                    .frame(width: 28)
                Text(size.title)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }
}
