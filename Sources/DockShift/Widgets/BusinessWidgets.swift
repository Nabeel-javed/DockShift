import Combine
import Security
import SwiftUI

/// Generic-password storage for API keys, so they never land in profiles.json.
enum Keychain {
    private static let service = "com.dockshift.DockShift"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        delete(account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Fetches revenue metrics from Stripe, Paddle and Shopify. Values are kept
/// until the next successful refresh so a failed call never blanks a tile.
@MainActor
final class BusinessService: ObservableObject {
    static let shared = BusinessService()

    struct Metrics {
        var currency: String
        /// Metric id → value, e.g. "revenue", "net", "mrr", "arr", "subscribers", "arpu", "orders", "aov".
        var values: [String: Double]
        /// Daily totals of the primary metric over the period, oldest first.
        var series: [Double]
        var fetchedAt: Date
    }

    @Published private(set) var metrics: [UUID: Metrics] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var loading: Set<UUID> = []
    private var shopifyTokens: [UUID: (token: String, expires: Date)] = [:]
    private var timers: [UUID: AnyCancellable] = [:]

    private init() {}

    static func keychainAccount(_ instance: WidgetInstance, _ field: String = "key") -> String {
        "\(instance.type.rawValue)-\(field)-\(instance.id.uuidString)"
    }

    static func isConnected(_ instance: WidgetInstance) -> Bool {
        switch instance.type {
        case .shopify:
            return Keychain.get(keychainAccount(instance, "client")) != nil
                && Keychain.get(keychainAccount(instance, "secret")) != nil
                && !(instance.settings["shop"] ?? "").isEmpty
        default:
            return Keychain.get(keychainAccount(instance)) != nil
        }
    }

    static func metricTitles(for type: WidgetType) -> [(id: String, title: String)] {
        switch type {
        case .stripe:
            return [("revenue", "Revenue"), ("net", "Net after fees"), ("mrr", "MRR"), ("arr", "ARR"), ("subscribers", "Paying subscribers"), ("arpu", "ARPU")]
        case .paddle:
            return [("net", "Net revenue"), ("mrr", "MRR"), ("arr", "ARR")]
        case .shopify:
            return [("revenue", "Order value"), ("orders", "Orders"), ("aov", "Average order")]
        default:
            return []
        }
    }

    func start(_ instance: WidgetInstance) {
        guard timers[instance.id] == nil else { return }
        refresh(instance)
        timers[instance.id] = Timer.publish(every: 5 * 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh(instance) }
    }

    func stop(_ instance: WidgetInstance) {
        timers[instance.id] = nil
    }

    func disconnect(_ instance: WidgetInstance) {
        for field in ["key", "client", "secret"] { Keychain.delete(BusinessService.keychainAccount(instance, field)) }
        metrics[instance.id] = nil
        errors[instance.id] = nil
        shopifyTokens[instance.id] = nil
    }

    func refresh(_ instance: WidgetInstance) {
        guard BusinessService.isConnected(instance), !loading.contains(instance.id) else { return }
        loading.insert(instance.id)
        let period = instance.settings["period"] ?? "mtd"
        Task {
            defer { loading.remove(instance.id) }
            do {
                let result: Metrics
                switch instance.type {
                case .stripe: result = try await fetchStripe(instance, period: period)
                case .paddle: result = try await fetchPaddle(instance, period: period)
                case .shopify: result = try await fetchShopify(instance, period: period)
                default: return
                }
                metrics[instance.id] = result
                errors[instance.id] = nil
            } catch {
                errors[instance.id] = (error as? BusinessError)?.message ?? error.localizedDescription
            }
        }
    }

    struct BusinessError: Error { var message: String }

    static func periodStart(_ period: String) -> Date {
        let calendar = Calendar.current
        if period == "l30" {
            return calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: Date())) ?? Date()
        }
        return calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    /// Buckets (date, amount) pairs into one total per day from `start` to today.
    static func dailySeries(_ entries: [(Date, Double)], from start: Date) -> [Double] {
        let calendar = Calendar.current
        let days = max(1, (calendar.dateComponents([.day], from: start, to: Date()).day ?? 0) + 1)
        var totals = Array(repeating: 0.0, count: days)
        for (date, amount) in entries {
            let index = calendar.dateComponents([.day], from: start, to: date).day ?? 0
            if totals.indices.contains(index) { totals[index] += amount }
        }
        return totals
    }

    static func monthly(_ amount: Double, interval: String, count: Int) -> Double {
        let per = Double(max(1, count))
        switch interval.lowercased() {
        case "day": return amount * 30 / per
        case "week": return amount * 52 / 12 / per
        case "year": return amount / 12 / per
        default: return amount / per
        }
    }

    // MARK: Stripe

    private func fetchStripe(_ instance: WidgetInstance, period: String) async throws -> Metrics {
        guard let key = Keychain.get(BusinessService.keychainAccount(instance)) else { throw BusinessError(message: "Not connected") }
        let start = BusinessService.periodStart(period)
        var entries: [(Date, Double)] = []
        var netEntries: [(Date, Double)] = []
        var currency = "usd"
        var startingAfter: String?
        for _ in 0..<5 {
            var url = "https://api.stripe.com/v1/balance_transactions?limit=100&created[gte]=\(Int(start.timeIntervalSince1970))"
            if let startingAfter { url += "&starting_after=\(startingAfter)" }
            let page = try await stripeGET(url, key: key)
            guard let data = page["data"] as? [[String: Any]] else { break }
            for transaction in data where ["charge", "payment"].contains(transaction["type"] as? String ?? "") {
                let date = Date(timeIntervalSince1970: transaction["created"] as? Double ?? 0)
                entries.append((date, (transaction["amount"] as? Double ?? 0) / 100))
                netEntries.append((date, (transaction["net"] as? Double ?? 0) / 100))
                currency = transaction["currency"] as? String ?? currency
            }
            guard page["has_more"] as? Bool == true, let last = data.last?["id"] as? String else { break }
            startingAfter = last
        }

        var mrr = 0.0
        var subscribers = 0.0
        let subscriptions = try await stripeGET("https://api.stripe.com/v1/subscriptions?status=active&limit=100", key: key)
        for subscription in subscriptions["data"] as? [[String: Any]] ?? [] {
            subscribers += 1
            let items = (subscription["items"] as? [String: Any])?["data"] as? [[String: Any]] ?? []
            for item in items {
                guard let price = item["price"] as? [String: Any], let recurring = price["recurring"] as? [String: Any] else { continue }
                let amount = (price["unit_amount"] as? Double ?? 0) / 100 * (item["quantity"] as? Double ?? 1)
                mrr += BusinessService.monthly(amount, interval: recurring["interval"] as? String ?? "month", count: recurring["interval_count"] as? Int ?? 1)
                currency = price["currency"] as? String ?? currency
            }
        }

        let revenue = entries.reduce(0) { $0 + $1.1 }
        let net = netEntries.reduce(0) { $0 + $1.1 }
        let primary = instance.settings["metric"] ?? "revenue"
        return Metrics(
            currency: currency.uppercased(),
            values: ["revenue": revenue, "net": net, "mrr": mrr, "arr": mrr * 12, "subscribers": subscribers, "arpu": subscribers > 0 ? mrr / subscribers : 0],
            series: BusinessService.dailySeries(primary == "net" ? netEntries : entries, from: start),
            fetchedAt: Date()
        )
    }

    private func stripeGET(_ url: String, key: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Stripe request failed"
            throw BusinessError(message: message)
        }
        return json
    }

    // MARK: Paddle

    private func fetchPaddle(_ instance: WidgetInstance, period: String) async throws -> Metrics {
        guard let key = Keychain.get(BusinessService.keychainAccount(instance)) else { throw BusinessError(message: "Not connected") }
        let base = key.contains("sdbx") ? "https://sandbox-api.paddle.com" : "https://api.paddle.com"
        let start = BusinessService.periodStart(period)
        let iso = ISO8601DateFormatter().string(from: start)
        var entries: [(Date, Double)] = []
        var currency = "USD"
        var after: String?
        for _ in 0..<5 {
            var url = "\(base)/transactions?status=completed&per_page=200&billed_at[GTE]=\(iso)"
            if let after { url += "&after=\(after)" }
            let page = try await paddleGET(url, key: key)
            let data = page["data"] as? [[String: Any]] ?? []
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for transaction in data {
                let billed = (transaction["billed_at"] as? String).flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? Date()
                let totals = (transaction["details"] as? [String: Any])?["totals"] as? [String: Any] ?? [:]
                let earnings = Double(totals["earnings"] as? String ?? "0") ?? 0
                entries.append((billed, earnings / 100))
                currency = totals["currency_code"] as? String ?? currency
            }
            let meta = (page["meta"] as? [String: Any])?["pagination"] as? [String: Any]
            guard meta?["has_more"] as? Bool == true, let last = data.last?["id"] as? String else { break }
            after = last
        }

        var mrr = 0.0
        let subscriptions = try await paddleGET("\(base)/subscriptions?status=active&per_page=200", key: key)
        for subscription in subscriptions["data"] as? [[String: Any]] ?? [] {
            for item in subscription["items"] as? [[String: Any]] ?? [] {
                guard let price = item["price"] as? [String: Any],
                      let unit = price["unit_price"] as? [String: Any],
                      let cycle = price["billing_cycle"] as? [String: Any] else { continue }
                let amount = (Double(unit["amount"] as? String ?? "0") ?? 0) / 100 * (item["quantity"] as? Double ?? 1)
                mrr += BusinessService.monthly(amount, interval: cycle["interval"] as? String ?? "month", count: cycle["frequency"] as? Int ?? 1)
            }
        }

        return Metrics(
            currency: currency,
            values: ["net": entries.reduce(0) { $0 + $1.1 }, "mrr": mrr, "arr": mrr * 12],
            series: BusinessService.dailySeries(entries, from: start),
            fetchedAt: Date()
        )
    }

    private func paddleGET(_ url: String, key: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            let message = ((json["error"] as? [String: Any])?["detail"] as? String) ?? "Paddle request failed"
            throw BusinessError(message: message)
        }
        return json
    }

    // MARK: Shopify

    private func fetchShopify(_ instance: WidgetInstance, period: String) async throws -> Metrics {
        guard let shop = instance.settings["shop"]?.trimmingCharacters(in: .whitespaces), !shop.isEmpty,
              let clientID = Keychain.get(BusinessService.keychainAccount(instance, "client")),
              let secret = Keychain.get(BusinessService.keychainAccount(instance, "secret"))
        else { throw BusinessError(message: "Not connected") }
        let host = shop.contains(".") ? shop : "\(shop).myshopify.com"

        var token = shopifyTokens[instance.id]
        if token == nil || token!.expires < Date() {
            var request = URLRequest(url: URL(string: "https://\(host)/admin/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "client_id=\(clientID)&client_secret=\(secret)&grant_type=client_credentials".data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard let accessToken = json["access_token"] as? String else {
                throw BusinessError(message: json["error_description"] as? String ?? "Shopify sign-in failed")
            }
            let expires = Date().addingTimeInterval((json["expires_in"] as? Double ?? 86400) - 60)
            token = (accessToken, expires)
            shopifyTokens[instance.id] = token
        }

        let start = BusinessService.periodStart(period)
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let query = """
        { orders(first: 250, query: "created_at:>=\(day.string(from: start))") { edges { node { createdAt currentTotalPriceSet { shopMoney { amount currencyCode } } } } } }
        """
        var request = URLRequest(url: URL(string: "https://\(host)/admin/api/2025-01/graphql.json")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token!.token, forHTTPHeaderField: "X-Shopify-Access-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let errors = json["errors"] as? [[String: Any]], let message = errors.first?["message"] as? String {
            throw BusinessError(message: message)
        }
        let edges = ((json["data"] as? [String: Any])?["orders"] as? [String: Any])?["edges"] as? [[String: Any]] ?? []
        let formatter = ISO8601DateFormatter()
        var entries: [(Date, Double)] = []
        var currency = "USD"
        for edge in edges {
            guard let node = edge["node"] as? [String: Any],
                  let money = (node["currentTotalPriceSet"] as? [String: Any])?["shopMoney"] as? [String: Any] else { continue }
            let date = (node["createdAt"] as? String).flatMap(formatter.date(from:)) ?? Date()
            entries.append((date, Double(money["amount"] as? String ?? "0") ?? 0))
            currency = money["currencyCode"] as? String ?? currency
        }
        let revenue = entries.reduce(0) { $0 + $1.1 }
        let orders = Double(entries.count)
        return Metrics(
            currency: currency,
            values: ["revenue": revenue, "orders": orders, "aov": orders > 0 ? revenue / orders : 0],
            series: BusinessService.dailySeries(entries, from: start),
            fetchedAt: Date()
        )
    }

    // MARK: Formatting

    static func format(_ value: Double, metric: String, currency: String) -> String {
        if metric == "subscribers" || metric == "orders" { return String(Int(value)) }
        let symbol: String
        switch currency.uppercased() {
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        case "NOK", "SEK", "DKK": symbol = "kr "
        default: symbol = currency.uppercased() + " "
        }
        let magnitude = abs(value)
        let text: String
        if magnitude >= 1_000_000 { text = String(format: "%.1fM", value / 1_000_000) }
        else if magnitude >= 10_000 { text = String(format: "%.1fK", value / 1_000) }
        else if magnitude >= 1_000 { text = String(format: "%.1fK", value / 1_000) }
        else { text = String(format: "%.0f", value) }
        return symbol + text
    }
}

// MARK: - Tile

struct BusinessTile: View {
    @ObservedObject private var service = BusinessService.shared
    let context: WidgetContext
    @State private var showDetails = false

    private var type: WidgetType { context.instance.type }
    private var metric: String { context.setting("metric", default: BusinessService.metricTitles(for: type).first?.id ?? "revenue") }
    private var period: String { context.setting("period", default: type == .paddle ? "latest" : "mtd") }
    private var label: String { context.setting("label", default: type.title) }

    private var dotColor: Color {
        switch type {
        case .stripe: return .cyan
        case .paddle: return .yellow
        case .shopify: return .green
        default: return .gray
        }
    }

    private var metrics: BusinessService.Metrics? {
        if context.isPreview {
            switch type {
            case .paddle: return .init(currency: "USD", values: ["net": 3500, "mrr": 3500, "arr": 42000], series: [2, 3, 2, 4, 3, 5, 4, 6, 5, 7], fetchedAt: Date())
            case .shopify: return .init(currency: "USD", values: ["revenue": 17200, "orders": 212, "aov": 81], series: [3, 2, 4, 3, 5, 4, 6, 5, 4, 6], fetchedAt: Date())
            default: return .init(currency: "USD", values: ["revenue": 2400, "net": 2290, "mrr": 1900, "arr": 22800], series: [1, 2, 2, 3, 2, 4, 3, 3, 4, 5], fetchedAt: Date())
            }
        }
        return service.metrics[context.id]
    }

    var body: some View {
        HStack(spacing: context.iconSize * 0.14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Circle().fill(dotColor).frame(width: context.iconSize * 0.1, height: context.iconSize * 0.1)
                    Text(label).font(context.smallFont).foregroundStyle(.secondary)
                }
                Text(valueText).font(context.valueFont).monospacedDigit()
                HStack {
                    Text(BusinessService.metricTitles(for: type).first { $0.id == metric }?.title ?? metric)
                    Spacer(minLength: 6)
                    Text(periodLabel)
                }
                .font(context.smallFont)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            if context.variant == "chart", let series = metrics?.series, series.count > 1 {
                Sparkline(values: series, color: dotColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: context.iconSize * 0.5)
            }
        }
        .padding(.horizontal, context.iconSize * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { showDetails.toggle() } }
        .popover(isPresented: $showDetails) { BusinessPopout(context: context) }
        .onAppear { if !context.isPreview { service.start(context.instance) } }
        .onDisappear { if !context.isPreview { service.stop(context.instance) } }
    }

    private var valueText: String {
        guard let metrics else {
            if !BusinessService.isConnected(context.instance) && !context.isPreview { return "Connect" }
            return service.errors[context.id] == nil ? "…" : "—"
        }
        return BusinessService.format(metrics.values[metric] ?? 0, metric: metric, currency: metrics.currency)
    }

    private var periodLabel: String {
        if ["mrr", "arr", "subscribers", "arpu"].contains(metric) { return "Latest" }
        return period == "l30" ? "L30" : "MTD"
    }
}

private struct BusinessPopout: View {
    @ObservedObject private var service = BusinessService.shared
    let context: WidgetContext

    var body: some View {
        let metrics = service.metrics[context.id]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(context.setting("label", default: context.instance.type.title)).font(.headline)
                Spacer()
                if service.loading.contains(context.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh") { service.refresh(context.instance) }.controlSize(.small)
                }
            }
            if !BusinessService.isConnected(context.instance) {
                Text("Right-click the widget and choose Configure widget… to connect your account.").foregroundStyle(.secondary)
            } else if let metrics {
                ForEach(BusinessService.metricTitles(for: context.instance.type), id: \.id) { entry in
                    HStack {
                        Text(entry.title)
                        Spacer()
                        Text(BusinessService.format(metrics.values[entry.id] ?? 0, metric: entry.id, currency: metrics.currency)).monospacedDigit()
                    }
                }
                Text("Updated \(TimeFormat.clock(metrics.fetchedAt))").font(.caption2).foregroundStyle(.secondary)
            }
            if let error = service.errors[context.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

struct BusinessConfig: View {
    @ObservedObject private var service = BusinessService.shared
    let context: WidgetContext
    @State private var key = ""
    @State private var clientID = ""
    @State private var secret = ""
    @State private var shop: String

    init(context: WidgetContext) {
        self.context = context
        _shop = State(initialValue: context.setting("shop") ?? "")
    }

    private var type: WidgetType { context.instance.type }
    private var connected: Bool { BusinessService.isConnected(context.instance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(type.title).font(.headline)
            TextField("Label (e.g. Studio)", text: Binding(
                get: { context.setting("label") ?? "" },
                set: { context.set("label", $0.isEmpty ? nil : $0) }
            ))
            Picker("Metric", selection: Binding(
                get: { context.setting("metric", default: BusinessService.metricTitles(for: type).first?.id ?? "") },
                set: { context.set("metric", $0) }
            )) {
                ForEach(BusinessService.metricTitles(for: type), id: \.id) { Text($0.title).tag($0.id) }
            }
            Picker("Period", selection: Binding(
                get: { context.setting("period", default: "mtd") },
                set: { context.set("period", $0) }
            )) {
                Text("Month to date").tag("mtd")
                Text("Last 30 days").tag("l30")
            }
            Divider()
            if connected {
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Disconnect") { service.disconnect(context.instance) }
            } else {
                switch type {
                case .shopify:
                    TextField("Store (yourstore.myshopify.com)", text: $shop)
                    TextField("Client ID", text: $clientID)
                    SecureField("Client secret", text: $secret)
                    Text("Create a custom app in the Shopify Dev Dashboard with read_orders access.").font(.caption).foregroundStyle(.secondary)
                    Button("Connect") {
                        context.set("shop", shop)
                        Keychain.set(clientID, for: BusinessService.keychainAccount(context.instance, "client"))
                        Keychain.set(secret, for: BusinessService.keychainAccount(context.instance, "secret"))
                        var updated = context.instance
                        updated.settings["shop"] = shop
                        service.refresh(updated)
                    }
                    .disabled(shop.isEmpty || clientID.isEmpty || secret.isEmpty)
                default:
                    SecureField(type == .stripe ? "Restricted API key (rk_…)" : "API key (pdl_…)", text: $key)
                    Text(type == .stripe
                         ? "Needs read access to Balance and Subscriptions. No write permissions."
                         : "Needs the metrics.read permission. Sandbox keys work too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Connect") {
                        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: BusinessService.keychainAccount(context.instance))
                        key = ""
                        service.refresh(context.instance)
                    }
                    .disabled(key.isEmpty)
                }
            }
            if let error = service.errors[context.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
    }
}
