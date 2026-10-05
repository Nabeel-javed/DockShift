import SwiftUI

/// A colored note whose first lines show in the Dock; click to edit.
struct StickyNoteTile: View {
    let context: WidgetContext
    @State private var showEditor = false

    static let colors: [(id: String, title: String, color: Color)] = [
        ("yellow", "Yellow", Color(red: 1.0, green: 0.86, blue: 0.4)),
        ("pink", "Pink", Color(red: 1.0, green: 0.68, blue: 0.75)),
        ("blue", "Blue", Color(red: 0.62, green: 0.8, blue: 1.0)),
        ("green", "Green", Color(red: 0.7, green: 0.9, blue: 0.65)),
        ("purple", "Purple", Color(red: 0.8, green: 0.7, blue: 1.0)),
        ("gray", "Gray", Color(white: 0.8)),
    ]

    static func color(for id: String) -> Color {
        colors.first { $0.id == id }?.color ?? colors[0].color
    }

    private var text: String {
        context.isPreview ? "Pick up coffee\nCall Alex" : context.setting("text", default: "")
    }

    var body: some View {
        Text(text.isEmpty ? "Click to write a note" : text)
            .font(.system(size: max(9, context.iconSize * 0.17), weight: .medium))
            .foregroundStyle(text.isEmpty ? Color.black.opacity(0.4) : Color.black.opacity(0.85))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, context.iconSize * 0.14)
            .padding(.vertical, context.iconSize * 0.1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(StickyNoteTile.color(for: context.setting("color", default: "yellow")))
            .contentShape(Rectangle())
            .onTapGesture { if !context.isPreview { showEditor.toggle() } }
            .popover(isPresented: $showEditor) {
                StickyNoteEditor(context: context)
            }
    }
}

private struct StickyNoteEditor: View {
    let context: WidgetContext
    @State private var text: String

    init(context: WidgetContext) {
        self.context = context
        _text = State(initialValue: context.setting("text", default: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sticky Note").font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(width: 260, height: 160)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(StickyNoteTile.color(for: context.setting("color", default: "yellow")).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: text) { newValue in context.set("text", newValue.isEmpty ? nil : newValue) }
        }
        .padding(12)
    }
}

struct StickyNoteConfig: View {
    let context: WidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sticky Note").font(.headline)
            Picker("Color", selection: Binding(
                get: { context.setting("color", default: "yellow") },
                set: { context.set("color", $0) }
            )) {
                ForEach(StickyNoteTile.colors, id: \.id) { entry in
                    HStack {
                        Circle().fill(entry.color).frame(width: 10, height: 10)
                        Text(entry.title)
                    }
                    .tag(entry.id)
                }
            }
        }
        .padding(12)
    }
}
