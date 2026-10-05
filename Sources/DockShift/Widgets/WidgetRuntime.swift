import AppKit
import Combine
import UserNotifications

/// Shared clock and timer state for widgets. Timers live here rather than in
/// views so they keep running while the Dock is hidden or re-rendered.
@MainActor
final class WidgetRuntime: ObservableObject {
    static let shared = WidgetRuntime()

    @Published private(set) var now = Date()
    @Published var stopwatches: [UUID: StopwatchState] = [:]
    @Published var focusTimers: [UUID: FocusTimerState] = [:]
    /// Alarms that already fired today, keyed by widget id.
    private var firedAlarms: [UUID: Date] = [:]
    private var cancellables = Set<AnyCancellable>()

    struct StopwatchState {
        var accumulated: TimeInterval = 0
        var startedAt: Date?

        var isRunning: Bool { startedAt != nil }

        func elapsed(at date: Date) -> TimeInterval {
            accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
        }
    }

    struct FocusTimerState {
        var duration: TimeInterval
        var remainingWhenPaused: TimeInterval
        var startedAt: Date?
        var completed = false

        var isRunning: Bool { startedAt != nil }

        func remaining(at date: Date) -> TimeInterval {
            guard let startedAt else { return remainingWhenPaused }
            return max(0, remainingWhenPaused - date.timeIntervalSince(startedAt))
        }
    }

    private init() {
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.tick(date) }
            .store(in: &cancellables)
    }

    private func tick(_ date: Date) {
        now = date
        for (id, state) in focusTimers where state.isRunning && !state.completed && state.remaining(at: date) <= 0 {
            var done = state
            done.startedAt = nil
            done.remainingWhenPaused = 0
            done.completed = true
            focusTimers[id] = done
            Notifier.notify(title: "Focus session complete", body: "Time for a break.", sound: "Glass")
        }
    }

    // MARK: Stopwatch

    func toggleStopwatch(_ id: UUID) {
        var state = stopwatches[id] ?? StopwatchState()
        if let startedAt = state.startedAt {
            state.accumulated += now.timeIntervalSince(startedAt)
            state.startedAt = nil
        } else {
            state.startedAt = Date()
        }
        stopwatches[id] = state
    }

    func resetStopwatch(_ id: UUID) {
        stopwatches[id] = StopwatchState()
    }

    // MARK: Focus timer

    func focusTimer(_ id: UUID, duration: TimeInterval) -> FocusTimerState {
        if let existing = focusTimers[id], existing.duration == duration { return existing }
        let fresh = FocusTimerState(duration: duration, remainingWhenPaused: duration)
        focusTimers[id] = fresh
        return fresh
    }

    func toggleFocusTimer(_ id: UUID, duration: TimeInterval) {
        var state = focusTimer(id, duration: duration)
        if state.completed {
            state = FocusTimerState(duration: duration, remainingWhenPaused: duration)
        }
        if let startedAt = state.startedAt {
            state.remainingWhenPaused = max(0, state.remainingWhenPaused - Date().timeIntervalSince(startedAt))
            state.startedAt = nil
        } else {
            state.startedAt = Date()
        }
        focusTimers[id] = state
    }

    func resetFocusTimer(_ id: UUID, duration: TimeInterval) {
        focusTimers[id] = FocusTimerState(duration: duration, remainingWhenPaused: duration)
    }

    // MARK: Alarm

    /// Fires the alarm once when the clock passes its time today.
    func checkAlarm(_ id: UUID, hour: Int, minute: Int, label: String, enabled: Bool) {
        guard enabled else { return }
        let calendar = Calendar.current
        guard let target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return }
        let alreadyFired = firedAlarms[id].map { calendar.isDate($0, inSameDayAs: now) } ?? false
        guard !alreadyFired, now >= target, now.timeIntervalSince(target) < 60 else { return }
        firedAlarms[id] = now
        Notifier.notify(title: label.isEmpty ? "Alarm" : label, body: TimeFormat.clock(target), sound: "Blow")
    }
}

/// User notifications for timers and alarms; silently degrades when not bundled.
enum Notifier {
    static func notify(title: String, body: String, sound: String) {
        NSSound(named: NSSound.Name(sound))?.play()
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}

enum TimeFormat {
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        clock.timeZone = timeZone
        return clock.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        shortDate.string(from: date)
    }

    /// "1:05:09" or "12:34" style durations.
    static func duration(_ interval: TimeInterval, showHours: Bool = false) -> String {
        let total = Int(interval.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 || showHours {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "2d 4h", "3h 12m", "45m" or "under a minute".
    static func remaining(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "under a minute"
    }
}
