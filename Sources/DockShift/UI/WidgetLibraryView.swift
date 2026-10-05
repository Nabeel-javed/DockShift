import SwiftUI

/// The Add Widget sheet: categories on the left, layouts to pick on the right.
struct WidgetLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category: WidgetCategory? = nil
    @State private var query = ""
    let onAdd: (WidgetInstance) -> Void

    private var visibleTypes: [WidgetType] {
        let base = category.map(\.types) ?? WidgetType.allCases
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.category.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            grid
        }
        .frame(width: 760, height: 520)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Add Widget", systemImage: "square.grid.2x2")
                .font(.headline)
            TextField("Search widgets", text: $query)
                .textFieldStyle(.roundedBorder)
            List(selection: $category) {
                Label("All Widgets", systemImage: "square.grid.2x2").tag(WidgetCategory?.none)
                ForEach(WidgetCategory.allCases) { category in
                    Label(category.title, systemImage: category.symbol).tag(WidgetCategory?.some(category))
                }
            }
            .listStyle(.sidebar)
        }
        .padding(12)
        .frame(width: 200)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groupedCategories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.title).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], alignment: .leading, spacing: 12) {
                                ForEach(visibleTypes.filter { $0.category == category }) { type in
                                    ForEach(type.variants, id: \.id) { variant in
                                        WidgetCard(type: type, variant: variant.id, variantTitle: variant.title) {
                                            onAdd(WidgetInstance(type: type, variant: variant.id))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Text("Click + to add a widget to this Dock. You can add the same widget more than once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    private var groupedCategories: [WidgetCategory] {
        WidgetCategory.allCases.filter { category in visibleTypes.contains { $0.category == category } }
    }
}

private struct WidgetCard: View {
    let type: WidgetType
    let variant: String
    let variantTitle: String
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetPreview(instance: WidgetInstance(type: type, variant: variant))
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text(type.variants.count > 1 ? "\(type.title) · \(variantTitle)" : type.title)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add to Dock")
            }
        }
    }
}

/// Static preview of a widget for the library. Real widgets replace this as
/// they are implemented.
struct WidgetPreview: View {
    let instance: WidgetInstance

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: instance.type.symbol)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.type.title).font(.caption.bold())
                if instance.type.variants.count > 1 {
                    Text(instance.variantTitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
    }
}
