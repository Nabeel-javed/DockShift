import SwiftUI

// MARK: - Clock

struct ClockTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    let context: WidgetContext

    private var now: Date { context.isPreview ? Date() : runtime.now }

    var body: some View {
        WidgetLabel(context: context, value: TimeFormat.clock(now), caption: TimeFormat.shortDate(now)) {
            ClockGlyph(date: now, size: context.iconSize * 0.5)
        }
    }
}

/// A tiny analog clock face.
struct ClockGlyph: View {
    let date: Date
    let size: CGFloat
    var timeZone: TimeZone = .current

    var body: some View {
        let components = Calendar.current.dateComponents(in: timeZone, from: date)
        let hour = Double(components.hour ?? 0).truncatingRemainder(dividingBy: 12)
        let minute = Double(components.minute ?? 0)
        ZStack {
            Circle().fill(.primary.opacity(0.1))
            Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1)
            Hand(angle: (hour + minute / 60) / 12 * 360, length: 0.28, width: 2)
            Hand(angle: minute / 60 * 360, length: 0.4, width: 1.5)
        }
        .frame(width: size, height: size)
    }

    private struct Hand: View {
        let angle: Double
        let length: Double
        let width: CGFloat

        var body: some View {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                Capsule()
                    .fill(.primary.opacity(0.85))
                    .frame(width: width, height: side * length)
                    .offset(y: -side * length / 2)
                    .rotationEffect(.degrees(angle))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

// MARK: - World clock

struct WorldClockTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    let context: WidgetContext

    private var zone: TimeZone {
        TimeZone(identifier: context.setting("timeZone", default: "Europe/London")) ?? .current
    }

    private var now: Date { context.isPreview ? Date() : runtime.now }

    var body: some View {
        WidgetLabel(context: context, value: TimeFormat.clock(now, timeZone: zone), caption: cityName) {
            ClockGlyph(date: now, size: context.iconSize * 0.5, timeZone: zone)
        }
    }

    private var cityName: String {
        if let label = context.setting("label"), !label.isEmpty { return label }
        return zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }
}

struct WorldClockConfig: View {
    let context: WidgetContext
    @State private var query = ""

    private var zones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") }
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("World Clock").font(.headline)
            TextField("Label (optional)", text: Binding(
                get: { context.setting("label") ?? "" },
                set: { context.set("label", $0.isEmpty ? nil : $0) }
            ))
            TextField("Search time zones", text: $query)
            List(zones, id: \.self, selection: Binding(
                get: { context.setting("timeZone") ?? "Europe/London" },
                set: { context.set("timeZone", $0) }
            )) { zone in
                Text(zone.replacingOccurrences(of: "_", with: " "))
            }
            .frame(height: 200)
        }
        .padding(12)
    }
}

// MARK: - Stopwatch

struct StopwatchTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    let context: WidgetContext

    private var state: WidgetRuntime.StopwatchState { runtime.stopwatches[context.id] ?? .init() }
    private var elapsed: TimeInterval { context.isPreview ? 0 : state.elapsed(at: runtime.now) }

    var body: some View {
        WidgetLabel(context: context,
                    value: TimeFormat.duration(elapsed),
                    caption: state.isRunning ? "Running" : (elapsed > 0 ? "Paused" : "Ready")) {
            Image(systemName: "stopwatch")
                .font(.system(size: context.iconSize * 0.34))
                .foregroundStyle(state.isRunning ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { runtime.toggleStopwatch(context.id) } }
        .contextMenu {
            Button(state.isRunning ? "Pause" : "Start") { runtime.toggleStopwatch(context.id) }
            Button("Reset") { runtime.resetStopwatch(context.id) }
        }
    }
}

// MARK: - Focus timer

struct FocusTimerTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    let context: WidgetContext

    private var duration: TimeInterval {
        (Double(context.setting("minutes", default: "25")) ?? 25) * 60
    }

    private var state: WidgetRuntime.FocusTimerState {
        context.isPreview
            ? .init(duration: duration, remainingWhenPaused: duration)
            : runtime.focusTimer(context.id, duration: duration)
    }

    private var remaining: TimeInterval { state.remaining(at: runtime.now) }

    var body: some View {
        WidgetLabel(context: context,
                    value: TimeFormat.duration(remaining),
                    caption: state.completed ? "Done" : (state.isRunning ? "Focus" : "Paused")) {
            RingView(progress: 1 - remaining / max(1, duration), lineWidth: context.iconSize * 0.07, color: .orange)
                .frame(width: context.iconSize * 0.5, height: context.iconSize * 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { runtime.toggleFocusTimer(context.id, duration: duration) } }
        .contextMenu {
            Button(state.isRunning ? "Pause" : "Start") { runtime.toggleFocusTimer(context.id, duration: duration) }
            Button("Reset") { runtime.resetFocusTimer(context.id, duration: duration) }
        }
    }
}

struct FocusTimerConfig: View {
    let context: WidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus Timer").font(.headline)
            Picker("Length", selection: Binding(
                get: { context.setting("minutes", default: "25") },
                set: { minutes in
                    context.set("minutes", minutes)
                    WidgetRuntime.shared.resetFocusTimer(context.id, duration: (Double(minutes) ?? 25) * 60)
                }
            )) {
                ForEach(["15", "25", "45", "60", "90"], id: \.self) { Text("\($0) min").tag($0) }
            }
            Text("Click the tile to start or pause.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

// MARK: - Time progress

struct TimeProgressTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    let context: WidgetContext

    private var period: String { context.setting("period", default: "year") }

    private var progress: (fraction: Double, label: String) {
        let calendar = Calendar.current
        let now = context.isPreview ? Date() : runtime.now
        let component: Calendar.Component
        let label: String
        switch period {
        case "day":
            component = .day
            label = TimeFormat.shortDate(now)
        case "week":
            component = .weekOfYear
            label = "Week \(calendar.component(.weekOfYear, from: now))"
        case "month":
            component = .month
            label = calendar.monthSymbols[calendar.component(.month, from: now) - 1]
        default:
            component = .year
            label = String(calendar.component(.year, from: now))
        }
        guard let interval = calendar.dateInterval(of: component, for: now) else { return (0, label) }
        return (now.timeIntervalSince(interval.start) / interval.duration, label)
    }

    var body: some View {
        let value = progress
        VStack(alignment: .leading, spacing: context.iconSize * 0.08) {
            HStack {
                Text(value.label).font(context.captionFont).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.fraction * 100))%").font(context.valueFont).monospacedDigit()
            }
            StripedBar(fraction: value.fraction)
                .frame(height: context.iconSize * 0.26)
        }
        .padding(.horizontal, context.iconSize * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Vertical tick marks filling left to right, like a progress ruler.
struct StripedBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            let count = max(10, Int(proxy.size.width / 5))
            let filled = Int(Double(count) * fraction)
            HStack(spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < filled ? Color.primary.opacity(0.85) : Color.primary.opacity(0.2))
                }
            }
        }
    }
}

struct TimeProgressConfig: View {
    let context: WidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time Progress").font(.headline)
            Picker("Period", selection: Binding(
                get: { context.setting("period", default: "year") },
                set: { context.set("period", $0) }
            )) {
                Text("Day").tag("day")
                Text("Week").tag("week")
                Text("Month").tag("month")
                Text("Year").tag("year")
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
    }
}

// MARK: - Countdown

struct CountdownTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    let context: WidgetContext

    private var target: Date? {
        context.setting("target").flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private var title: String { context.setting("title", default: "Countdown") }

    var body: some View {
        let now = context.isPreview ? Date() : runtime.now
        let value: String
        if context.isPreview {
            value = "5:00"
        } else if let target {
            let remaining = target.timeIntervalSince(now)
            value = remaining <= 0 ? "Done" : (remaining < 3600 ? TimeFormat.duration(remaining) : TimeFormat.remaining(remaining))
        } else {
            value = "Set a date"
        }
        return WidgetLabel(context: context, value: value, caption: title) {
            Image(systemName: "hourglass")
                .font(.system(size: context.iconSize * 0.34))
                .foregroundStyle(.secondary)
        }
    }
}

struct CountdownConfig: View {
    let context: WidgetContext
    @State private var date: Date
    @State private var title: String

    init(context: WidgetContext) {
        self.context = context
        _date = State(initialValue: context.setting("target").flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date().addingTimeInterval(3600))
        _title = State(initialValue: context.setting("title") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Countdown").font(.headline)
            TextField("Title", text: $title)
            DatePicker("Ends", selection: $date)
            HStack {
                Spacer()
                Button("Save") {
                    context.set([
                        "target": ISO8601DateFormatter().string(from: date),
                        "title": title.isEmpty ? nil : title,
                    ])
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}

// MARK: - Alarm

struct AlarmTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    let context: WidgetContext

    private var hour: Int { Int(context.setting("hour", default: "10")) ?? 10 }
    private var minute: Int { Int(context.setting("minute", default: "50")) ?? 50 }
    private var label: String { context.setting("label", default: "Alarm") }
    private var enabled: Bool { context.setting("enabled", default: "true") == "true" }

    private var alarmDate: Date {
        let now = context.isPreview ? Date() : runtime.now
        var target = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if target < now { target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target }
        return target
    }

    var body: some View {
        let now = context.isPreview ? Date() : runtime.now
        WidgetLabel(context: context,
                    value: TimeFormat.clock(alarmDate),
                    caption: label,
                    trailing: enabled ? "in " + TimeFormat.remaining(alarmDate.timeIntervalSince(now)) : "off") {
            Image(systemName: enabled ? "alarm.fill" : "alarm")
                .font(.system(size: context.iconSize * 0.34))
                .foregroundStyle(enabled ? Color.orange : .secondary)
        }
        .onReceive(runtime.$now) { _ in
            if !context.isPreview {
                runtime.checkAlarm(context.id, hour: hour, minute: minute, label: label, enabled: enabled)
            }
        }
        .contextMenu {
            Button(enabled ? "Turn Off" : "Turn On") { context.set("enabled", enabled ? "false" : "true") }
        }
    }
}

struct AlarmConfig: View {
    let context: WidgetContext
    @State private var time: Date
    @State private var label: String

    init(context: WidgetContext) {
        self.context = context
        let hour = Int(context.setting("hour", default: "10")) ?? 10
        let minute = Int(context.setting("minute", default: "50")) ?? 50
        _time = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date())
        _label = State(initialValue: context.setting("label") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alarm").font(.headline)
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            TextField("Label", text: $label)
            Toggle("Enabled", isOn: Binding(
                get: { context.setting("enabled", default: "true") == "true" },
                set: { context.set("enabled", $0 ? "true" : "false") }
            ))
            HStack {
                Spacer()
                Button("Save") {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                    context.set([
                        "hour": String(components.hour ?? 0),
                        "minute": String(components.minute ?? 0),
                        "label": label.isEmpty ? nil : label,
                    ])
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}
