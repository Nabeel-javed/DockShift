import AppKit
import Combine
import EventKit

/// Shared access to Calendar and Reminders for the widgets. Keeps today's and
/// tomorrow's events and all incomplete reminders fresh.
@MainActor
final class EventKitStore: ObservableObject {
    static let shared = EventKitStore()

    let store = EKEventStore()
    @Published private(set) var calendarAccess = false
    @Published private(set) var reminderAccess = false
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var reminders: [EKReminder] = []
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var reminderLists: [EKCalendar] = []

    private var cancellables = Set<AnyCancellable>()

    private init() {
        calendarAccess = EventKitStore.hasAccess(to: .event)
        reminderAccess = EventKitStore.hasAccess(to: .reminder)

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    static func hasAccess(to type: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: type)
        if #available(macOS 14, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    func requestCalendarAccess() {
        Task {
            calendarAccess = (try? await requestAccess(to: .event)) ?? false
            refresh()
        }
    }

    func requestReminderAccess() {
        Task {
            reminderAccess = (try? await requestAccess(to: .reminder)) ?? false
            refresh()
        }
    }

    private func requestAccess(to type: EKEntityType) async throws -> Bool {
        if #available(macOS 14, *) {
            return type == .event
                ? try await store.requestFullAccessToEvents()
                : try await store.requestFullAccessToReminders()
        }
        return try await store.requestAccess(to: type)
    }

    func refresh() {
        if calendarAccess {
            calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        }
        if reminderAccess {
            reminderLists = store.calendars(for: .reminder).sorted { $0.title < $1.title }
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: predicate) { [weak self] found in
                let sorted = (found ?? []).sorted { lhs, rhs in
                    switch (lhs.dueDate, rhs.dueDate) {
                    case let (l?, r?): return l < r
                    case (nil, _?): return false
                    case (_?, nil): return true
                    default: return (lhs.title ?? "") < (rhs.title ?? "")
                    }
                }
                Task { @MainActor in self?.reminders = sorted }
            }
        }
    }

    // MARK: Queries

    func events(inCalendars ids: Set<String>, includeAllDay: Bool) -> [EKEvent] {
        events.filter { event in
            (ids.isEmpty || ids.contains(event.calendar.calendarIdentifier)) && (includeAllDay || !event.isAllDay)
        }
    }

    func reminders(inList id: String?) -> [EKReminder] {
        guard let id, !id.isEmpty else { return reminders }
        return reminders.filter { $0.calendar.calendarIdentifier == id }
    }

    // MARK: Editing reminders

    func setCompleted(_ reminder: EKReminder, _ completed: Bool) {
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
        refresh()
    }

    func addReminder(title: String, listID: String?) {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = reminderLists.first { $0.calendarIdentifier == listID } ?? store.defaultCalendarForNewReminders()
        try? store.save(reminder, commit: true)
        refresh()
    }
}

extension EKReminder {
    var dueDate: Date? {
        dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    }
}

extension EKEvent {
    /// A video call link found in the URL, location or notes.
    var meetingURL: URL? {
        let sources = [url?.absoluteString, location, notes].compactMap { $0 }
        let pattern = #"https?://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com|whereby\.com|meet\.jit\.si)[^\s<>"]*"#
        for source in sources {
            if let range = source.range(of: pattern, options: .regularExpression) {
                return URL(string: String(source[range]))
            }
        }
        return nil
    }

    var calendarColor: NSColor {
        calendar.color ?? .systemBlue
    }
}
