import AppKit
import SwiftUI

/// A read-only rendering of a profile's items as a Dock, shown in the editor
/// so changes are visible before they are applied.
struct DockPreviewStrip: View {
    let items: [DockItem]
    let kind: ProfileKind

    private let iconSize: CGFloat = 36
    private var gap: CGFloat { 7 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: gap) {
                if items.isEmpty {
                    Text(kind == .customDock ? "Add widgets, apps, folders, files or links" : "Add apps and spacers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    tile(for: item)
                }
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
        .frame(height: iconSize + 20)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func tile(for item: DockItem) -> some View {
        switch item {
        case .app(let app):
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .help(app.label)
        case .file(let file):
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .help(file.name)
        case .folder(let folder):
            VStack(spacing: 1) {
                FolderIcon(folder: folder)
                    .frame(width: folder.showName ? iconSize * 0.7 : iconSize, height: folder.showName ? iconSize * 0.7 : iconSize)
                if folder.showName {
                    Text(folder.name).font(.system(size: 7)).lineLimit(1)
                }
            }
            .frame(width: iconSize, height: iconSize)
            .help(folder.name)
        case .link(let link):
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.08))
                Image(systemName: link.symbol ?? "link").font(.system(size: 15)).foregroundStyle(.primary.opacity(0.8))
            }
            .frame(width: iconSize, height: iconSize)
            .help(link.name)
        case .spacer(let size):
            Rectangle()
                .fill(.clear)
                .frame(width: size == .small ? iconSize * 0.3 : iconSize * 0.6, height: iconSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.vertical, 6)
                )
        case .widget(let widget):
            let units = CGFloat(widget.widthUnits)
            WidgetView(context: WidgetContext(instance: widget, iconSize: iconSize, isPreview: true))
                .frame(width: units * iconSize + (units - 1) * gap, height: iconSize)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.primary.opacity(widgetDrawsOwnBackground(widget.type) ? 0 : 0.07))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .allowsHitTesting(false)
                .help(widget.type.title)
        }
    }
}
