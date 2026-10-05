import Combine
import Foundation
import SwiftUI

/// Token activity from local AI coding tool logs, plus remaining allowances
/// when a status-line bridge has written them.
///
/// Activity: Claude Code (~/.claude/projects/**.jsonl) and Codex
/// (~/.codex/sessions/**.jsonl) record token usage per message.
/// Limits: tools can write `~/Library/Application Support/DockShift/ai-limits.json`
/// as {"claude": {"percentLeft": 72, "resetsAt": "2026-10-05T12:00:00Z"}, ...}.
@MainActor
final class AIUsageService: ObservableObject {
    static let shared = AIUsageService()

    enum Provider: String, CaseIterable, Identifiable {
        case claude, codex

        var id: String { rawValue }
        var title: String { self == .claude ? "Claude" : "Codex" }
        var color: Color { self == .claude ? .orange : .teal }
    }

    struct Activity {
        var tokensByDay: [Date: Double]
        var sessions: Int

        func total(since start: Date) -> Double {
            tokensByDay.filter { $0.key >= start }.values.reduce(0, +)
        }

        func series(days: Int) -> [Double] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            return (0..<days).reversed().map { offset in
                let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
                return tokensByDay[day] ?? 0
            }
        }
    }

    struct Limit {
        var percentLeft: Double
        var resetsAt: Date?
    }

    @Published private(set) var activity: [Provider: Activity] = [:]
    @Published private(set) var limits: [Provider: Limit] = [:]
    @Published private(set) var lastScan: Date?
    private var timer: AnyCancellable?
    private var interest = 0
    private var scanning = false

    private init() {}

    func retain() {
        interest += 1
        if timer == nil {
            scan()
            timer = Timer.publish(every: 120, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.scan() }
        }
    }

    func release() {
        interest = max(0, interest - 1)
        if interest == 0 { timer = nil }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        Task.detached(priority: .utility) {
            let claude = AIUsageService.scanJSONL(root: "~/.claude/projects", provider: .claude)
            let codex = AIUsageService.scanJSONL(root: "~/.codex/sessions", provider: .codex)
            let limits = AIUsageService.readLimits()
            await MainActor.run {
                self.activity = [.claude: claude, .codex: codex]
                self.limits = limits
                self.lastScan = Date()
                self.scanning = false
            }
        }
    }

    nonisolated private static func scanJSONL(root: String, provider: Provider) -> Activity {
        let base = URL(fileURLWithPath: NSString(string: root).expandingTildeInPath)
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -31, to: Date()) ?? Date()
        var tokensByDay: [Date: Double] = [:]
        var sessions = 0
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return Activity(tokensByDay: [:], sessions: 0)
        }
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified >= cutoff,
                  let data = FileManager.default.contents(atPath: url.path),
                  let text = String(data: data, encoding: .utf8) else { continue }
            sessions += 1
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                guard let (date, tokens) = extract(object, provider: provider), date >= cutoff else { continue }
                tokensByDay[calendar.startOfDay(for: date), default: 0] += tokens
            }
        }
        return Activity(tokensByDay: tokensByDay, sessions: sessions)
    }

    nonisolated private static func extract(_ object: [String: Any], provider: Provider) -> (Date, Double)? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: Any?) -> Date? {
            guard let string = value as? String else { return nil }
            return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        }
        switch provider {
        case .claude:
            guard let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any] else { return nil }
            let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                .reduce(0.0) { $0 + (usage[$1] as? Double ?? 0) }
            guard tokens > 0, let when = date(object["timestamp"]) else { return nil }
            return (when, tokens)
        case .codex:
            guard let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any] else { return nil }
            let tokens = ["input_tokens", "output_tokens", "cached_input_tokens"].reduce(0.0) { $0 + (last[$1] as? Double ?? 0) }
            guard tokens > 0, let when = date(object["timestamp"]) else { return nil }
            return (when, tokens)
        }
    }

    nonisolated private static func readLimits() -> [Provider: Limit] {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DockShift/ai-limits.json")
        guard let data = FileManager.default.contents(atPath: url.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [Provider: Limit] = [:]
        for provider in Provider.allCases {
            guard let entry = json[provider.rawValue] as? [String: Any], let percent = entry["percentLeft"] as? Double else { continue }
            let resets = (entry["resetsAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            result[provider] = Limit(percentLeft: percent, resetsAt: resets)
        }
        return result
    }

    static func formatTokens(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return String(Int(value))
    }
}

// MARK: - Tile

struct AIUsageTile: View {
    @ObservedObject private var service = AIUsageService.shared
    let context: WidgetContext
    @State private var showDetails = false

    private var providers: [AIUsageService.Provider] {
        let chosen = context.setting("providers", default: "claude,codex").split(separator: ",").compactMap { AIUsageService.Provider(rawValue: String($0)) }
        return chosen.isEmpty ? AIUsageService.Provider.allCases : chosen
    }

    private var range: String { context.setting("range", default: "today") }

    private var rangeStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch range {
        case "l7": return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case "l30": return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case "mtd": return calendar.dateInterval(of: .month, for: today)?.start ?? today
        default: return today
        }
    }

    private func percentLeft(_ provider: AIUsageService.Provider) -> Double? {
        if context.isPreview { return provider == .claude ? 54 : 72 }
        return service.limits[provider]?.percentLeft
    }

    private func tokens(_ provider: AIUsageService.Provider) -> Double {
        if context.isPreview { return provider == .claude ? 1_240_000 : 860_000 }
        return service.activity[provider]?.total(since: rangeStart) ?? 0
    }

    var body: some View {
        HStack(spacing: context.iconSize * 0.2) {
            ForEach(providers.prefix(3)) { provider in
                providerView(provider)
            }
        }
        .padding(.horizontal, context.iconSize * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { showDetails.toggle() } }
        .popover(isPresented: $showDetails) { AIUsagePopout(context: context, providers: providers) }
        .onAppear { if !context.isPreview { service.retain() } }
        .onDisappear { if !context.isPreview { service.release() } }
    }

    @ViewBuilder
    private func providerView(_ provider: AIUsageService.Provider) -> some View {
        let left = percentLeft(provider)
        switch context.variant {
        case "rings":
            VStack(spacing: 1) {
                ZStack {
                    RingView(progress: (left ?? 0) / 100, lineWidth: context.iconSize * 0.07, color: provider.color)
                    Text(left.map { "\(Int($0))" } ?? AIUsageService.formatTokens(tokens(provider)))
                        .font(.system(size: context.iconSize * 0.14, weight: .semibold)).monospacedDigit()
                }
                .frame(width: context.iconSize * 0.52, height: context.iconSize * 0.52)
                Text(provider.title).font(context.smallFont).foregroundStyle(.secondary)
            }
        case "bars":
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(provider.title).font(context.smallFont)
                    Spacer()
                    Text(left.map { "\(Int($0))%" } ?? AIUsageService.formatTokens(tokens(provider))).font(context.smallFont.weight(.semibold)).monospacedDigit()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.12))
                        Capsule().fill(provider.color).frame(width: proxy.size.width * CGFloat((left ?? 100) / 100))
                    }
                }
                .frame(height: context.iconSize * 0.08)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                Text(left.map { "\(Int($0))%" } ?? AIUsageService.formatTokens(tokens(provider)))
                    .font(context.valueFont).monospacedDigit()
                Text(left != nil ? "\(provider.title) left" : "\(provider.title) tokens")
                    .font(context.smallFont).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

private struct AIUsagePopout: View {
    @ObservedObject private var service = AIUsageService.shared
    let context: WidgetContext
    let providers: [AIUsageService.Provider]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Usage").font(.headline)
                Spacer()
                Button("Refresh") { service.scan() }.controlSize(.small)
            }
            ForEach(providers) { provider in
                let activity = service.activity[provider]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(provider.color).frame(width: 8, height: 8)
                        Text(provider.title).bold()
                        Spacer()
                        if let limit = service.limits[provider] {
                            Text("\(Int(limit.percentLeft))% left" + (limit.resetsAt.map { " · resets \(TimeFormat.clock($0))" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let activity {
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: Date())
                        HStack(spacing: 12) {
                            stat("Today", activity.total(since: today))
                            stat("L7", activity.total(since: calendar.date(byAdding: .day, value: -6, to: today) ?? today))
                            stat("L30", activity.total(since: calendar.date(byAdding: .day, value: -29, to: today) ?? today))
                            stat("MTD", activity.total(since: calendar.dateInterval(of: .month, for: today)?.start ?? today))
                        }
                        HStack(alignment: .bottom, spacing: 2) {
                            let series = activity.series(days: 30)
                            let peak = max(series.max() ?? 1, 1)
                            ForEach(Array(series.enumerated()), id: \.offset) { _, value in
                                RoundedRectangle(cornerRadius: 1).fill(provider.color).frame(height: max(1, 28 * value / peak))
                            }
                        }
                        .frame(height: 28, alignment: .bottom)
                        Text("\(activity.sessions) sessions in the last 31 days").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("No local sessions found.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Totals include cached tokens. Limits appear when a status-line bridge writes ai-limits.json.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AIUsageService.formatTokens(value)).font(.callout.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct AIUsageConfig: View {
    let context: WidgetContext

    private var selected: Set<String> {
        Set(context.setting("providers", default: "claude,codex").split(separator: ",").map(String.init))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Usage").font(.headline)
            ForEach(AIUsageService.Provider.allCases) { provider in
                Toggle(provider.title, isOn: Binding(
                    get: { selected.contains(provider.rawValue) },
                    set: { on in
                        var ids = selected
                        if on { ids.insert(provider.rawValue) } else { ids.remove(provider.rawValue) }
                        context.set("providers", ids.sorted().joined(separator: ","))
                    }
                ))
            }
            Picker("Activity range", selection: Binding(
                get: { context.setting("range", default: "today") },
                set: { context.set("range", $0) }
            )) {
                Text("Today").tag("today")
                Text("Last 7 days").tag("l7")
                Text("Last 30 days").tag("l30")
                Text("Month to date").tag("mtd")
            }
            Text("Reads Claude Code and Codex session logs on this Mac.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
