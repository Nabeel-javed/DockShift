import AppKit
import EventKit
import SwiftUI

/// Calendar widget: next event, date + next event, date + agenda, or date only.
struct CalendarTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    @ObservedObject private var eventKit = EventKitStore.shared
    let context: WidgetContext
    @State private var showAgenda = false

    private var includeAllDay: Bool { context.setting("allDay", default: "false") == "true" }
    private var showCallButton: Bool { context.setting("callButton", default: "true") == "true" }
    private var calendarIDs: Set<String> {
        Set(context.setting("calendars", default: "").split(separator: ",").map(String.init))
    }

    private var now: Date { context.isPreview ? Date() : runtime.now }

    private var todaysEvents: [EKEvent] {
        eventKit.events(inCalendars: calendarIDs, includeAllDay: includeAllDay)
            .filter { Calendar.current.isDate($0.startDate, inSameDayAs: now) && $0.endDate > now }
    }

    /// The event to feature: one starting within 30 minutes, else an ongoing
    /// one, else the next one today.
    private var featured: EKEvent? {
        let events = todaysEvents
        if let soon = events.first(where: { $0.startDate > now && $0.startDate.timeIntervalSince(now) <= 1800 }) { return soon }
        if let ongoing = events.first(where: { $0.startDate <= now && $0.endDate > now }) { return ongoing }
        return events.first { $0.startDate > now }
    }

    var body: some View {
        Group {
            switch context.variant {
            case "date":
                DateBlock(date: now, size: context.iconSize)
            case "dateNextEvent":
                HStack(spacing: context.iconSize * 0.14) {
                    DateBlock(date: now, size: context.iconSize * 0.78)
                    eventSummary
                    callButton
                }
                .padding(.horizontal, context.iconSize * 0.14)
            case "dateAgenda":
                HStack(spacing: context.iconSize * 0.14) {
                    DateBlock(date: now, size: context.iconSize * 0.78)
                    agendaList
                }
                .padding(.horizontal, context.iconSize * 0.14)
            default:
                HStack(spacing: context.iconSize * 0.12) {
                    eventSummary
                    callButton
                }
                .padding(.horizontal, context.iconSize * 0.16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { showAgenda.toggle() } }
        .popover(isPresented: $showAgenda) {
            AgendaPopout(context: context, calendarIDs: calendarIDs, includeAllDay: includeAllDay)
        }
    }

    @ViewBuilder
    private var eventSummary: some View {
        if context.isPreview {
            EventSummary(context: context, title: "Design review", time: "10:30", color: .orange)
        } else if !eventKit.calendarAccess {
            EventSummary(context: context, title: "Calendar access needed", time: "Right-click to set up", color: .gray)
        } else if let event = featured {
            EventSummary(
                context: context,
                title: event.title ?? "Untitled",
                time: event.isAllDay ? "All day" : TimeFormat.clock(event.startDate),
                color: Color(nsColor: event.calendarColor)
            )
        } else {
            EventSummary(context: context, title: "No more events", time: "Today", color: .gray)
        }
    }

    private var agendaList: some View {
        let events = context.isPreview ? [] : Array(todaysEvents.prefix(3))
        return VStack(alignment: .leading, spacing: 1) {
            if context.isPreview {
                AgendaRow(context: context, title: "Design review", time: "10:30", color: .orange)
                AgendaRow(context: context, title: "Lunch with Alex", time: "12:00", color: .green)
                AgendaRow(context: context, title: "Team catch-up", time: "14:00", color: .blue)
            } else if events.isEmpty {
                Text(eventKit.calendarAccess ? "No more events today" : "Calendar access needed")
                    .font(context.captionFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events, id: \.eventIdentifier) { event in
                    AgendaRow(context: context,
                              title: event.title ?? "Untitled",
                              time: event.isAllDay ? "All day" : TimeFormat.clock(event.startDate),
                              color: Color(nsColor: event.calendarColor))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var callButton: some View {
        if showCallButton, let url = context.isPreview ? URL(string: "https://meet.google.com") : featured?.meetingURL {
            Button {
                if !context.isPreview { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "video.fill")
                    .font(.system(size: context.iconSize * 0.24))
                    .frame(width: context.iconSize * 0.5, height: context.iconSize * 0.5)
                    .background(Circle().fill(.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Join call")
        }
    }
}

private struct EventSummary: View {
    let context: WidgetContext
    let title: String
    let time: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: context.iconSize * 0.1, height: context.iconSize * 0.1)
                Text(title).font(context.captionFont.weight(.medium))
            }
            Text(time).font(context.valueFont).monospacedDigit()
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgendaRow: View {
    let context: WidgetContext
    let title: String
    let time: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: context.iconSize * 0.09, height: context.iconSize * 0.09)
            Text(title).font(context.smallFont.weight(.medium))
            Spacer(minLength: 4)
            Text(time).font(context.smallFont).foregroundStyle(.secondary).monospacedDigit()
        }
        .lineLimit(1)
    }
}

/// "MON" over a large day number, like a tear-off calendar.
struct DateBlock: View {
    let date: Date
    let size: CGFloat

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: -size * 0.04) {
            Text(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1].uppercased())
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(.red)
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: size * 0.46, weight: .medium, design: .rounded))
        }
        .frame(width: size * 0.9, height: size * 0.9)
        .background(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(.primary.opacity(0.08)))
    }
}

private struct AgendaPopout: View {
    @ObservedObject private var eventKit = EventKitStore.shared
    let context: WidgetContext
    let calendarIDs: Set<String>
    let includeAllDay: Bool

    private var days: [(title: String, events: [EKEvent])] {
        let all = eventKit.events(inCalendars: calendarIDs, includeAllDay: includeAllDay)
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return [
            ("Today", all.filter { Calendar.current.isDate($0.startDate, inSameDayAs: today) }),
            ("Tomorrow", all.filter { Calendar.current.isDate($0.startDate, inSameDayAs: tomorrow) }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !eventKit.calendarAccess {
                Text("Calendar").font(.headline)
                Text("Allow access to show your events.").foregroundStyle(.secondary)
                Button("Allow Calendar Access") { eventKit.requestCalendarAccess() }
            } else {
                ForEach(days, id: \.title) { day in
                    Text(day.title).font(.headline)
                    if day.events.isEmpty {
                        Text("No events").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(day.events, id: \.eventIdentifier) { event in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(nsColor: event.calendarColor))
                                .frame(width: 4, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title ?? "Untitled").lineLimit(1)
                                Text(event.isAllDay ? "All day" : "\(TimeFormat.clock(event.startDate)) – \(TimeFormat.clock(event.endDate))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = event.meetingURL {
                                Button("Join") { NSWorkspace.shared.open(url) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct CalendarConfig: View {
    @ObservedObject private var eventKit = EventKitStore.shared
    let context: WidgetContext

    private var selected: Set<String> {
        Set(context.setting("calendars", default: "").split(separator: ",").map(String.init))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar").font(.headline)
            if !eventKit.calendarAccess {
                Button("Allow Calendar Access") { eventKit.requestCalendarAccess() }
            }
            Toggle("Include all-day events", isOn: Binding(
                get: { context.setting("allDay", default: "false") == "true" },
                set: { context.set("allDay", $0 ? "true" : "false") }
            ))
            Toggle("Show call button", isOn: Binding(
                get: { context.setting("callButton", default: "true") == "true" },
                set: { context.set("callButton", $0 ? "true" : "false") }
            ))
            if !eventKit.calendars.isEmpty {
                Text("Calendars").font(.subheadline.bold())
                Text(selected.isEmpty ? "Showing all calendars" : "Showing \(selected.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(eventKit.calendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: Binding(
                                get: { selected.isEmpty || selected.contains(calendar.calendarIdentifier) },
                                set: { on in
                                    var ids = selected.isEmpty ? Set(eventKit.calendars.map(\.calendarIdentifier)) : selected
                                    if on { ids.insert(calendar.calendarIdentifier) } else { ids.remove(calendar.calendarIdentifier) }
                                    let all = ids.count == eventKit.calendars.count
                                    context.set("calendars", all ? nil : ids.sorted().joined(separator: ","))
                                }
                            )) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(nsColor: calendar.color ?? .systemBlue)).frame(width: 8, height: 8)
                                    Text(calendar.title)
                                    Text(calendar.source.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(12)
    }
}
