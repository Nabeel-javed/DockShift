import SwiftUI

/// Everything a widget view needs: its instance, how big to draw, and a way
/// to persist settings changes.
struct WidgetContext {
    var instance: WidgetInstance
    var iconSize: CGFloat
    var isPreview: Bool = false
    var isVertical: Bool = false
    var update: (WidgetInstance) -> Void = { _ in }

    var id: UUID { instance.id }
    var variant: String { instance.variant }

    func setting(_ key: String) -> String? { instance.settings[key] }

    func setting(_ key: String, default fallback: String) -> String {
        instance.settings[key] ?? fallback
    }

    func set(_ key: String, _ value: String?) {
        var changed = instance
        changed.settings[key] = value
        update(changed)
    }

    func set(_ values: [String: String?]) {
        var changed = instance
        for (key, value) in values { changed.settings[key] = value }
        update(changed)
    }

    /// Scaled type sizes so widgets look right at any Dock size.
    var titleFont: Font { .system(size: iconSize * 0.3, weight: .semibold, design: .rounded) }
    var valueFont: Font { .system(size: iconSize * 0.26, weight: .semibold, design: .rounded) }
    var captionFont: Font { .system(size: max(9, iconSize * 0.16)) }
    var smallFont: Font { .system(size: max(8, iconSize * 0.14)) }
}

/// Dispatches to the view for a widget family. Families without a dedicated
/// view yet show a labelled placeholder.
struct WidgetView: View {
    let context: WidgetContext

    var body: some View {
        switch context.instance.type {
        case .clock: ClockTile(context: context)
        case .worldClock: WorldClockTile(context: context)
        case .stopwatch: StopwatchTile(context: context)
        case .focusTimer: FocusTimerTile(context: context)
        case .timeProgress: TimeProgressTile(context: context)
        case .countdown: CountdownTile(context: context)
        case .alarm: AlarmTile(context: context)
        default: PlaceholderTile(context: context)
        }
    }
}

/// Whether the family has a configuration popover.
func widgetHasConfiguration(_ type: WidgetType) -> Bool {
    switch type {
    case .clock, .stopwatch: return false
    case .worldClock, .focusTimer, .timeProgress, .countdown, .alarm: return true
    default: return false
    }
}

/// Dispatches to a family's configuration view.
struct WidgetConfigView: View {
    let context: WidgetContext

    var body: some View {
        Group {
            switch context.instance.type {
            case .worldClock: WorldClockConfig(context: context)
            case .focusTimer: FocusTimerConfig(context: context)
            case .timeProgress: TimeProgressConfig(context: context)
            case .countdown: CountdownConfig(context: context)
            case .alarm: AlarmConfig(context: context)
            default: Text("Nothing to configure.").padding()
            }
        }
        .frame(width: 280)
    }
}

/// Standard two-line widget body: a leading glyph, a value and a caption.
struct WidgetLabel<Leading: View>: View {
    let context: WidgetContext
    let value: String
    let caption: String
    var trailing: String? = nil
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: context.iconSize * 0.12) {
            leading()
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(context.valueFont)
                    .monospacedDigit()
                Text(caption)
                    .font(context.captionFont)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            if let trailing {
                Spacer(minLength: 0)
                Text(trailing)
                    .font(context.smallFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, context.iconSize * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PlaceholderTile: View {
    let context: WidgetContext

    var body: some View {
        WidgetLabel(context: context, value: context.instance.type.title,
                    caption: context.instance.type.variants.count > 1 ? context.instance.variantTitle : "Coming soon") {
            Image(systemName: context.instance.type.symbol)
                .font(.system(size: context.iconSize * 0.34))
                .foregroundStyle(.primary.opacity(0.7))
        }
    }
}

/// A circular progress ring used by timers and percentages.
struct RingView: View {
    var progress: Double
    var lineWidth: CGFloat
    var color: Color = .accentColor

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
