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
                selection = store.activeProfileID ?? store.activeCustomProfileID ?? store.profiles.first?.id
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
                ForEach(ProfileKind.allCases, id: \.self) { kind in
                    let group = store.profiles(of: kind)
                    if !group.isEmpty {
                        Section(kind.title) {
                            ForEach(group) { profile in
                                ProfileRow(profile: profile, isActive: store.isActive(profile))
                                    .tag(profile.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                NewProfileMenu { created in selection = created.id }
                Spacer()
            }
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 320)
    }
}

/// "New profile" menu offering both Dock kinds.
private struct NewProfileMenu: View {
    @EnvironmentObject private var store: ProfileStore
    let onCreated: (DockProfile) -> Void

    var body: some View {
        Menu {
            Section("macOS Dock") {
                Button("Create from Current Dock") {
                    onCreated(store.createFromCurrentDock(name: "Dock \(store.profiles(of: .macOSDock).count + 1)"))
                }
                Button("Start Empty") {
                    onCreated(store.createEmpty(name: "New Dock", kind: .macOSDock))
                }
            }
            Section("Custom Dock") {
                Button("New Custom Dock") {
                    onCreated(store.createEmpty(name: "Custom Dock", kind: .customDock))
                }
            }
        } label: {
            Label("New profile", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
                    .help("Currently in use")
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
            Button("Or create a Custom Dock with widgets") {
                onCreated(store.createEmpty(name: "Custom Dock", kind: .customDock))
            }
            .buttonStyle(.link)
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail

struct EditorItem: Identifiable {
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
    @State private var showWidgetLibrary = false
    @State private var linkSheet: LinkSheetTarget?
    @State private var folderSheet: FolderSheetTarget?

    init(profile: DockProfile) {
        self.profile = profile
        _draft = State(initialValue: profile)
        _items = State(initialValue: profile.items.map { EditorItem(item: $0) })
    }

    private var saved: DockProfile { store.profile(id: profile.id) ?? profile }
    private var isActive: Bool { store.isActive(saved) }
    private var isCustom: Bool { profile.kind == .customDock }

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
        .sheet(isPresented: $showWidgetLibrary) {
            WidgetLibraryView { instance in
                items.append(EditorItem(item: .widget(instance)))
            }
        }
        .sheet(item: $linkSheet) { target in
            LinkEditorSheet(link: target.link) { edited in
                if let index = items.firstIndex(where: { $0.id == target.itemID }) {
                    items[index].item = .link(edited)
                } else {
                    items.append(EditorItem(item: .link(edited)))
                }
            }
        }
        .sheet(item: $folderSheet) { target in
            FolderCustomizeSheet(folder: target.folder) { edited in
                replace(target.id, with: .folder(edited))
            }
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

            VStack(alignment: .leading, spacing: 0) {
                TextField("Dock name", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .onSubmit(save)
                Text(profile.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            Menu("Profile actions") {
                if !isCustom {
                    Button("Replace with Current Dock…") { confirmReplace = true }
                }
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
                    Text(isCustom ? "Nothing in this Dock yet" : "No apps yet")
                        .font(.headline)
                    Text(isCustom
                         ? "Use Add to place widgets, apps, folders, files and links."
                         : "Use Add to pin apps and spacers to this Dock.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedItems) {
                    ForEach(items) { entry in
                        DockItemRow(item: entry.item)
                            .tag(entry.id)
                            .contextMenu { rowMenu(for: entry) }
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

    @ViewBuilder
    private func rowMenu(for entry: EditorItem) -> some View {
        switch entry.item {
        case .folder(let folder):
            Button("Customize Folder…") { folderSheet = FolderSheetTarget(id: entry.id, folder: folder) }
        case .link(let link):
            Button("Edit Link…") { linkSheet = LinkSheetTarget(itemID: entry.id, link: link) }
        case .widget(let widget) where widget.type.variants.count > 1:
            Menu("Layout") {
                ForEach(widget.type.variants, id: \.id) { variant in
                    Button {
                        var changed = widget
                        changed.variant = variant.id
                        replace(entry.id, with: .widget(changed))
                    } label: {
                        if variant.id == widget.variant {
                            Label(variant.title, systemImage: "checkmark")
                        } else {
                            Text(variant.title)
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
        Button("Remove") { items.removeAll { $0.id == entry.id } }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                if isCustom {
                    Button("Widget…") { showWidgetLibrary = true }
                }
                Button("Apps…", action: pickApps)
                if isCustom {
                    Button("Folders…", action: pickFolders)
                    Button("Files…", action: pickFiles)
                    Button("Link…") {
                        linkSheet = LinkSheetTarget(itemID: nil, link: LinkReference(urlString: "https://", name: ""))
                    }
                }
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

            Text("\(items.count) items")
                .foregroundStyle(.secondary)
                .font(.callout)

            Button("Save Changes", action: save)
                .disabled(!isDirty)

            Button(isActive ? "Apply Changes" : "Use this profile") {
                save()
                store.apply(profile.id)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isActive && !isDirty && (isCustom || saved.items == DockBridge.currentItems()))
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

    private func replace(_ id: UUID, with item: DockItem) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].item = item
        }
    }

    private func removeSelected() {
        items.removeAll { selectedItems.contains($0.id) }
        selectedItems.removeAll()
    }

    private func pickApps() {
        let panel = NSOpenPanel()
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

    private func pickFolders() {
        let panel = NSOpenPanel()
        panel.message = "Select one or more folders."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            items.append(EditorItem(item: .folder(FolderReference(url: url))))
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.message = "Select one or more files."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            items.append(EditorItem(item: .file(FileReference(url: url))))
        }
    }
}

private struct FolderSheetTarget: Identifiable {
    var id: UUID
    var folder: FolderReference
}

private struct LinkSheetTarget: Identifiable {
    var itemID: UUID?
    var link: LinkReference
    var id: UUID { itemID ?? UUID(0) }
}

private extension UUID {
    /// A stable identifier for "new link" sheets.
    init(_ constant: Int) {
        self.init(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", constant))")!
    }
}

// MARK: - Rows

private struct DockItemRow: View {
    let item: DockItem

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Not found at the saved path.")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .app(let app):
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable()
        case .file(let file):
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable()
        case .folder(let folder):
            FolderIcon(folder: folder)
        case .link(let link):
            Image(systemName: link.symbol ?? "link")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        case .widget(let widget):
            Image(systemName: widget.type.symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
        case .spacer(let size):
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                .foregroundStyle(.secondary)
                .frame(width: size == .small ? 14 : 28, height: 28)
        }
    }

    private var title: String {
        switch item {
        case .app(let app): return app.label
        case .file(let file): return file.name
        case .folder(let folder): return folder.name
        case .link(let link): return link.name.isEmpty ? link.urlString : link.name
        case .widget(let widget): return widget.type.title
        case .spacer(let size): return size.title
        }
    }

    private var subtitle: String {
        switch item {
        case .app(let app): return app.path
        case .file(let file): return file.path
        case .folder(let folder): return folder.path
        case .link(let link): return link.urlString
        case .widget(let widget): return widget.type.variants.count > 1 ? widget.variantTitle : widget.type.category.title
        case .spacer: return "Gap between items"
        }
    }

    private var isMissing: Bool {
        switch item {
        case .app(let app): return !app.isInstalled
        case .file(let file): return !file.exists
        case .folder(let folder): return !folder.exists
        default: return false
        }
    }
}

/// A folder glyph in the folder's color with its optional letter.
struct FolderIcon: View {
    let folder: FolderReference

    var body: some View {
        ZStack {
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(folder.color.color.gradient)
            if !folder.letter.isEmpty {
                Text(folder.letter.prefix(1).uppercased())
                    .font(.system(size: 100, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.05)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 6)
                    .padding(.horizontal, 6)
            }
        }
    }
}

// MARK: - Sheets

private struct LinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link: LinkReference
    let onSave: (LinkReference) -> Void

    private static let symbols = ["link", "globe", "safari", "star.fill", "bookmark.fill", "doc.text", "envelope", "bubble.left", "play.rectangle", "cart", "chart.bar", "terminal"]

    init(link: LinkReference, onSave: @escaping (LinkReference) -> Void) {
        _link = State(initialValue: link)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link").font(.headline)
            Form {
                TextField("Name", text: $link.name)
                TextField("URL", text: $link.urlString)
                Picker("Icon", selection: $link.symbol) {
                    Text("Website icon").tag(String?.none)
                    ForEach(LinkEditorSheet.symbols, id: \.self) { symbol in
                        Label(symbol, systemImage: symbol).tag(String?.some(symbol))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if link.name.isEmpty, let host = link.url?.host { link.name = host }
                    onSave(link)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(link.url == nil || link.url?.host == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct FolderCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var folder: FolderReference
    let onSave: (FolderReference) -> Void

    init(folder: FolderReference, onSave: @escaping (FolderReference) -> Void) {
        _folder = State(initialValue: folder)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FolderIcon(folder: folder).frame(width: 48, height: 48)
                Text("Customize Folder").font(.headline)
            }
            Form {
                TextField("Name", text: $folder.name)
                TextField("Letter", text: Binding(
                    get: { folder.letter },
                    set: { folder.letter = String($0.prefix(1)) }
                ))
                Picker("Color", selection: $folder.color) {
                    ForEach(ProfileColor.allCases) { color in
                        Label(color.title, systemImage: "circle.fill").tag(color)
                    }
                }
                Toggle("Show name below icon", isOn: $folder.showName)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(folder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
