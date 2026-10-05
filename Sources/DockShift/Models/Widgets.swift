import Foundation

/// The widget library, grouped the way the Add Widget sheet shows it.
enum WidgetCategory: String, CaseIterable, Identifiable {
    case clocks, reminders, calendar, stickyNotes, media, system, weather, business, stocks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clocks: return "Clocks"
        case .reminders: return "Reminders"
        case .calendar: return "Calendar"
        case .stickyNotes: return "Sticky Notes"
        case .media: return "Media"
        case .system: return "System"
        case .weather: return "Weather"
        case .business: return "Business"
        case .stocks: return "Stocks"
        }
    }

    var symbol: String {
        switch self {
        case .clocks: return "clock"
        case .reminders: return "checklist"
        case .calendar: return "calendar"
        case .stickyNotes: return "note.text"
        case .media: return "play.rectangle"
        case .system: return "desktopcomputer"
        case .weather: return "cloud.sun"
        case .business: return "chart.line.uptrend.xyaxis"
        case .stocks: return "chart.xyaxis.line"
        }
    }

    var types: [WidgetType] { WidgetType.allCases.filter { $0.category == self } }
}

/// A widget family. Most families offer several layouts (`variants`).
enum WidgetType: String, Codable, CaseIterable, Identifiable {
    case clock, worldClock, stopwatch, focusTimer, timeProgress, countdown, alarm
    case reminders, hydration
    case calendar
    case stickyNote
    case nowPlaying
    case battery, systemActivity, network, aiUsage, shortcut, airDrop
    case weather
    case stripe, paddle, shopify
    case stock, watchlist

    var id: String { rawValue }

    var category: WidgetCategory {
        switch self {
        case .clock, .worldClock, .stopwatch, .focusTimer, .timeProgress, .countdown, .alarm: return .clocks
        case .reminders, .hydration: return .reminders
        case .calendar: return .calendar
        case .stickyNote: return .stickyNotes
        case .nowPlaying: return .media
        case .battery, .systemActivity, .network, .aiUsage, .shortcut, .airDrop: return .system
        case .weather: return .weather
        case .stripe, .paddle, .shopify: return .business
        case .stock, .watchlist: return .stocks
        }
    }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .worldClock: return "World Clock"
        case .stopwatch: return "Stopwatch"
        case .focusTimer: return "Focus Timer"
        case .timeProgress: return "Time Progress"
        case .countdown: return "Countdown"
        case .alarm: return "Alarm"
        case .reminders: return "Reminders"
        case .hydration: return "Hydration"
        case .calendar: return "Calendar"
        case .stickyNote: return "Sticky Note"
        case .nowPlaying: return "Now Playing"
        case .battery: return "Battery"
        case .systemActivity: return "System Activity"
        case .network: return "Network"
        case .aiUsage: return "AI Usage"
        case .shortcut: return "Shortcut"
        case .airDrop: return "AirDrop"
        case .weather: return "Weather"
        case .stripe: return "Stripe"
        case .paddle: return "Paddle"
        case .shopify: return "Shopify"
        case .stock: return "Stock"
        case .watchlist: return "Watchlist"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .worldClock: return "globe"
        case .stopwatch: return "stopwatch"
        case .focusTimer: return "timer"
        case .timeProgress: return "chart.bar.fill"
        case .countdown: return "hourglass"
        case .alarm: return "alarm"
        case .reminders: return "checklist"
        case .hydration: return "drop.fill"
        case .calendar: return "calendar"
        case .stickyNote: return "note.text"
        case .nowPlaying: return "music.note"
        case .battery: return "battery.75"
        case .systemActivity: return "cpu"
        case .network: return "network"
        case .aiUsage: return "sparkles"
        case .shortcut: return "square.stack.3d.up.fill"
        case .airDrop: return "airplayaudio"
        case .weather: return "cloud.sun.fill"
        case .stripe, .paddle, .shopify: return "chart.line.uptrend.xyaxis"
        case .stock: return "chart.xyaxis.line"
        case .watchlist: return "list.bullet.rectangle"
        }
    }

    /// Layout variants, as (identifier, display name). The first is the default.
    var variants: [(id: String, title: String)] {
        switch self {
        case .reminders: return [("list", "List"), ("next", "Next reminder"), ("count", "Count")]
        case .calendar:
            return [("nextEvent", "Next event"), ("dateNextEvent", "Date + next event"),
                    ("dateAgenda", "Date + agenda"), ("date", "Date")]
        case .nowPlaying: return [("full", "Full"), ("mini", "Mini")]
        case .battery: return [("status", "Status"), ("ring", "Percentage ring"), ("icon", "Icon only")]
        case .systemActivity: return [("numbers", "Numbers"), ("rings", "Rings"), ("bars", "Bars")]
        case .network: return [("numbers", "Numbers only"), ("chart", "With chart")]
        case .aiUsage: return [("numbers", "Numbers"), ("rings", "Rings"), ("bars", "Bars")]
        case .weather: return [("current", "Current"), ("conditions", "Conditions"), ("hourly", "Hourly forecast")]
        case .stripe, .paddle, .shopify: return [("chart", "With chart"), ("number", "Number only")]
        default: return [("standard", title)]
        }
    }

    /// Width in tile units for a layout, so the Dock can size tiles deterministically.
    func widthUnits(for variant: String) -> Double {
        switch (self, variant) {
        case (.clock, _), (.worldClock, _), (.stopwatch, _), (.focusTimer, _), (.countdown, _): return 2
        case (.timeProgress, _), (.alarm, _), (.hydration, _): return 3
        case (.reminders, "count"): return 1
        case (.reminders, "next"): return 3
        case (.reminders, _): return 4
        case (.calendar, "date"): return 1
        case (.calendar, "nextEvent"): return 3
        case (.calendar, "dateAgenda"): return 5
        case (.calendar, _): return 4
        case (.stickyNote, _): return 3
        case (.nowPlaying, "mini"): return 1
        case (.nowPlaying, _): return 5
        case (.battery, _): return 4
        case (.systemActivity, _): return 3
        case (.network, "chart"): return 3
        case (.network, _): return 2
        case (.aiUsage, _): return 3
        case (.shortcut, _), (.airDrop, _): return 2
        case (.weather, "current"): return 2
        case (.weather, "hourly"): return 4
        case (.weather, _): return 3
        case (.stripe, "number"), (.paddle, "number"), (.shopify, "number"): return 2
        case (.stripe, _), (.paddle, _), (.shopify, _): return 3
        case (.stock, _): return 3
        case (.watchlist, _): return 4
        }
    }

    var defaultVariant: String { variants[0].id }
}

/// A widget placed in a Custom Dock, with its chosen layout and settings.
struct WidgetInstance: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var type: WidgetType
    var variant: String
    var settings: [String: String] = [:]

    init(type: WidgetType, variant: String? = nil) {
        self.type = type
        self.variant = variant ?? type.defaultVariant
    }

    var variantTitle: String {
        type.variants.first { $0.id == variant }?.title ?? variant
    }

    var widthUnits: Double { type.widthUnits(for: variant) }
}
