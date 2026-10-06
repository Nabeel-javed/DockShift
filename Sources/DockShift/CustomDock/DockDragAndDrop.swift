import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drag types that only make sense inside DockShift.
extension UTType {
    /// A tile being rearranged within the Custom Dock (its index in the profile).
    static let dockShiftTile = UTType(importedAs: "com.dockshift.dock-tile")
    /// A running app's bundle path, dragged to keep it in the Dock.
    static let dockShiftPinApp = UTType(importedAs: "com.dockshift.pin-app")
}

/// Tracks a tile dragged out of the Custom Dock: dropped back on the Dock it
/// moves, dropped anywhere else it is removed with a poof, like Apple's Dock.
@MainActor
final class DockDragState: ObservableObject {
    @Published private(set) var draggingIndex: Int?
    /// Set by a drop target inside the Dock that accepted the drag.
    var dropHandled = false
    /// The Dock's bar on screen.
    var barRect: NSRect = .zero
    var removeItem: (Int) -> Void = { _ in }

    private var watcher: Timer?
    private var releasedAt: Date?

    func beginDrag(index: Int) {
        draggingIndex = index
        dropHandled = false
        releasedAt = nil
        watcher?.invalidate()
        // A drag runs its own event loop; this fires once it has ended.
        watcher = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDragEnded() }
        }
    }

    private func checkDragEnded() {
        guard let index = draggingIndex else { return finish() }
        if NSEvent.pressedMouseButtons != 0 {
            releasedAt = nil
            return
        }
        // Give a drop inside the Dock a moment to report itself.
        guard let releasedAt else { self.releasedAt = Date(); return }
        guard Date().timeIntervalSince(releasedAt) > 0.15 else { return }
        let mouse = NSEvent.mouseLocation
        if !dropHandled, !barRect.insetBy(dx: -30, dy: -30).contains(mouse) {
            NSAnimationEffect.disappearingItemDefault.show(centeredAt: mouse, size: .zero)
            removeItem(index)
        }
        finish()
    }

    private func finish() {
        watcher?.invalidate()
        watcher = nil
        draggingIndex = nil
        releasedAt = nil
    }
}

/// Turning dropped files and links into Dock items.
enum DockDrop {
    static func item(for url: URL) -> DockItem {
        if url.pathExtension == "app" { return .app(AppReference(url: url)) }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder(FolderReference(url: url))
        }
        return .file(FileReference(url: url))
    }

    /// File URLs carried by the providers, in order.
    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
        }
        return urls
    }

    /// The Dock items for whatever was dropped: files and folders, apps
    /// dragged from the running-apps section, and web links.
    static func items(from providers: [NSItemProvider]) async -> [DockItem] {
        var items: [DockItem] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    items.append(item(for: url))
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.dockShiftPinApp.identifier) {
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.dockShiftPinApp.identifier) as? Data,
                   let path = String(data: data, encoding: .utf8) {
                    items.append(.app(AppReference(url: URL(fileURLWithPath: path))))
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil), url.host != nil {
                    items.append(.link(LinkReference(urlString: url.absoluteString, name: url.host ?? url.absoluteString)))
                }
            }
        }
        return items
    }
}

/// Drops on the Dock's bar: rearranging a tile, or pinning dropped files,
/// apps and links where they land.
struct DockBarDropDelegate: DropDelegate {
    let layout: DockLayout
    let profile: DockProfile
    let store: ProfileStore
    let drag: DockDragState

    static let acceptedTypes: [UTType] = [.dockShiftTile, .dockShiftPinApp, .fileURL, .url]

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: Self.acceptedTypes)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: info.hasItemsConforming(to: [.dockShiftTile]) ? .move : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = insertionIndex(at: info.location)
        if info.hasItemsConforming(to: [.dockShiftTile]), let from = drag.draggingIndex {
            drag.dropHandled = true
            store.updateItems(of: profile.id) { items in
                guard items.indices.contains(from) else { return }
                items.move(fromOffsets: IndexSet(integer: from), toOffset: min(target, items.count))
            }
            return true
        }
        let providers = info.itemProviders(for: Self.acceptedTypes)
        let store = self.store
        let profileID = profile.id
        Task { @MainActor in
            let newItems = await DockDrop.items(from: providers)
            guard !newItems.isEmpty else { return }
            store.updateItems(of: profileID) { items in
                items.insert(contentsOf: newItems, at: min(target, items.count))
            }
        }
        return true
    }

    /// Which slot among the profile's items a point along the Dock falls in.
    private func insertionIndex(at location: CGPoint) -> Int {
        let position = layout.isVertical ? location.y : location.x
        var cursor: CGFloat = 0
        for (index, item) in profile.items.enumerated() where !layout.isHidden(item) {
            let length = layout.length(of: item)
            if position < cursor + length / 2 { return index }
            cursor += length + layout.gap
        }
        return profile.items.count
    }
}
