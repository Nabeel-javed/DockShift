import AppKit
import EventKit
import SwiftUI

/// Reminders widget: list, next reminder, or count.
struct RemindersTile: View {
    @ObservedObject private var eventKit = EventKitStore.shared
    let context: WidgetContext
    @State private var showList = false

    private var listID: String? { context.setting("list") }

    private var listName: String {
        if let listID, let list = eventKit.reminderLists.first(where: { $0.calendarIdentifier == listID }) {
            return list.title
        }
        return "All"
    }

    private var reminders: [EKReminder] { eventKit.reminders(inList: listID) }

    private var titles: [String] {
        context.isPreview
            ? ["Plan the weekend", "Pick up groceries", "Book an appointment"]
            : reminders.prefix(3).map { $0.title ?? "Untitled" }
    }

    private var count: Int { context.isPreview ? 3 : reminders.count }

    var body: some View {
        HStack(spacing: context.iconSize * 0.14) {
            countBadge
            if context.variant == "list" {
                VStack(alignment: .leading, spacing: 0) {
                    if !eventKit.reminderAccess && !context.isPreview {
                        Text("Reminders access needed").font(context.captionFont).foregroundStyle(.secondary)
                    } else if titles.isEmpty {
                        Text("All done").font(context.captionFont).foregroundStyle(.secondary)
                    } else {
                        ForEach(titles, id: \.self) { title in
                            Text(title).font(context.smallFont.weight(.medium)).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if context.variant == "next" {
                Text(titles.first ?? (eventKit.reminderAccess || context.isPreview ? "All done" : "Access needed"))
                    .font(context.captionFont.weight(.medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, context.variant == "count" ? 0 : context.iconSize * 0.14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { showList.toggle() } }
        .popover(isPresented: $showList) {
            RemindersPopout(context: context, listID: listID, listName: listName)
        }
    }

    private var countBadge: some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.system(size: context.iconSize * 0.24))
                    .foregroundStyle(.blue)
                Text("\(count)").font(context.valueFont).monospacedDigit()
            }
            Text(listName).font(context.smallFont).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: context.variant == "count" ? context.iconSize : nil)
    }
}

private struct RemindersPopout: View {
    @ObservedObject private var eventKit = EventKitStore.shared
    let context: WidgetContext
    let listID: String?
    let listName: String
    @State private var newTitle = ""
    @State private var justCompleted: EKReminder?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(listName == "All" ? "Reminders" : listName).font(.headline)
                Spacer()
                if let justCompleted {
                    Button("Undo") {
                        eventKit.setCompleted(justCompleted, false)
                        self.justCompleted = nil
                    }
                    .controlSize(.small)
                }
            }
            if !eventKit.reminderAccess {
                Text("Allow access to show your reminders.").foregroundStyle(.secondary)
                Button("Allow Reminders Access") { eventKit.requestReminderAccess() }
            } else {
                let reminders = eventKit.reminders(inList: listID)
                if reminders.isEmpty {
                    Text("Nothing to do").foregroundStyle(.secondary).font(.callout)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    eventKit.setCompleted(reminder, true)
                                    justCompleted = reminder
                                } label: {
                                    Image(systemName: "circle")
                                        .foregroundStyle(Color(nsColor: reminder.calendar.color ?? .systemBlue))
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(reminder.title ?? "Untitled")
                                    if let due = reminder.dueDate {
                                        Text(due < Date() ? "Overdue · \(TimeFormat.shortDate(due))" : TimeFormat.shortDate(due))
                                            .font(.caption)
                                            .foregroundStyle(due < Date() ? .red : .secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
                HStack {
                    TextField("Add a reminder", text: $newTitle)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        eventKit.addReminder(title: title, listID: listID)
        newTitle = ""
    }
}

struct RemindersConfig: View {
    @ObservedObject private var eventKit = EventKitStore.shared
    let context: WidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reminders").font(.headline)
            if !eventKit.reminderAccess {
                Button("Allow Reminders Access") { eventKit.requestReminderAccess() }
            }
            Picker("List", selection: Binding(
                get: { context.setting("list") ?? "" },
                set: { context.set("list", $0.isEmpty ? nil : $0) }
            )) {
                Text("All lists").tag("")
                ForEach(eventKit.reminderLists, id: \.calendarIdentifier) { list in
                    Text(list.title).tag(list.calendarIdentifier)
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Hydration

/// Counts down to the next drink and logs amounts through the day.
struct HydrationTile: View {
    @ObservedObject private var runtime = WidgetRuntime.shared
    let context: WidgetContext
    @State private var showLog = false

    private var interval: TimeInterval { (Double(context.setting("interval", default: "60")) ?? 60) * 60 }
    private var amount: Int { Int(context.setting("amount", default: "250")) ?? 250 }
    private var goal: Int { Int(context.setting("goal", default: "2000")) ?? 2000 }

    /// "timestamp,amount;timestamp,amount" for today only.
    private var log: [(Date, Int)] {
        context.setting("log", default: "").split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: ",")
            guard parts.count == 2, let ts = Double(parts[0]), let ml = Int(parts[1]) else { return nil }
            return (Date(timeIntervalSince1970: ts), ml)
        }
    }

    private var todayLog: [(Date, Int)] {
        log.filter { Calendar.current.isDateInToday($0.0) }
    }

    private var todayTotal: Int { todayLog.reduce(0) { $0 + $1.1 } }

    private var nextDrinkIn: TimeInterval {
        let now = context.isPreview ? Date() : runtime.now
        guard let last = todayLog.last?.0 else { return 0 }
        return max(0, last.addingTimeInterval(interval).timeIntervalSince(now))
    }

    var body: some View {
        let remaining = context.isPreview ? 1800 : nextDrinkIn
        VStack(spacing: 0) {
            Text(remaining > 0 ? TimeFormat.duration(remaining) : "Drink")
                .font(context.valueFont)
                .monospacedDigit()
            Text(remaining > 0 ? "Next drink" : "\(todayTotal) / \(goal) ml")
                .font(context.captionFont)
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.25, green: 0.6, blue: 0.95), Color(red: 0.1, green: 0.4, blue: 0.8)],
                           startPoint: .top, endPoint: .bottom)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { showLog.toggle() } }
        .popover(isPresented: $showLog) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hydration").font(.headline)
                Text("\(todayTotal) of \(goal) ml today").foregroundStyle(.secondary)
                ProgressView(value: min(1, Double(todayTotal) / Double(max(1, goal))))
                HStack {
                    ForEach([150, amount, 500].sorted(), id: \.self) { ml in
                        Button("+\(ml) ml") { logDrink(ml) }
                    }
                }
                if !todayLog.isEmpty {
                    Text("Logged today").font(.subheadline.bold())
                    ForEach(Array(todayLog.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(TimeFormat.clock(entry.0)).foregroundStyle(.secondary)
                            Text("\(entry.1) ml")
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(14)
            .frame(width: 260)
        }
    }

    private func logDrink(_ ml: Int) {
        var entries = todayLog
        entries.append((Date(), ml))
        let encoded = entries.map { "\(Int($0.0.timeIntervalSince1970)),\($0.1)" }.joined(separator: ";")
        context.set("log", encoded)
    }
}

struct HydrationConfig: View {
    let context: WidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hydration").font(.headline)
            Picker("Remind every", selection: Binding(
                get: { context.setting("interval", default: "60") },
                set: { context.set("interval", $0) }
            )) {
                ForEach(["30", "45", "60", "90", "120"], id: \.self) { Text("\($0) min").tag($0) }
            }
            Picker("Drink size", selection: Binding(
                get: { context.setting("amount", default: "250") },
                set: { context.set("amount", $0) }
            )) {
                ForEach(["200", "250", "300", "350", "500"], id: \.self) { Text("\($0) ml").tag($0) }
            }
            Picker("Daily goal", selection: Binding(
                get: { context.setting("goal", default: "2000") },
                set: { context.set("goal", $0) }
            )) {
                ForEach(["1500", "2000", "2500", "3000"], id: \.self) { Text("\($0) ml").tag($0) }
            }
        }
        .padding(12)
    }
}
