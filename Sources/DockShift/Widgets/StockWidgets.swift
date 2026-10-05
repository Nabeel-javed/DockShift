import Combine
import SwiftUI

/// Quotes and intraday history from Yahoo Finance's public chart endpoint.
@MainActor
final class StockService: ObservableObject {
    static let shared = StockService()

    struct Quote {
        var symbol: String
        var name: String
        var price: Double
        var previousClose: Double
        var currency: String
        var history: [Double]
        var range: String
        var fetchedAt: Date

        var change: Double { price - previousClose }
        var changePercent: Double { previousClose > 0 ? change / previousClose * 100 : 0 }
    }

    struct SearchResult: Identifiable {
        var id: String { symbol }
        var symbol: String
        var name: String
    }

    @Published private(set) var quotes: [String: Quote] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var inFlight = Set<String>()

    static let ranges: [(id: String, title: String, interval: String)] = [
        ("1d", "1D", "5m"), ("5d", "5D", "30m"), ("1mo", "1M", "1d"), ("6mo", "6M", "1d"), ("1y", "1Y", "1wk"),
    ]

    private init() {}

    func quote(for symbol: String, range: String = "1d") -> Quote? {
        let key = symbol.uppercased()
        if let cached = quotes[key], cached.range == range, Date().timeIntervalSince(cached.fetchedAt) < 5 * 60 {
            return cached
        }
        fetch(key, range: range)
        return quotes[key]
    }

    func refresh(_ symbol: String, range: String) {
        quotes[symbol.uppercased()] = nil
        fetch(symbol.uppercased(), range: range)
    }

    private func fetch(_ symbol: String, range: String) {
        let flightKey = "\(symbol)|\(range)"
        guard !inFlight.contains(flightKey) else { return }
        inFlight.insert(flightKey)
        let interval = StockService.ranges.first { $0.id == range }?.interval ?? "5m"
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        components.queryItems = [.init(name: "range", value: range), .init(name: "interval", value: interval), .init(name: "includePrePost", value: "false")]
        Task {
            defer { inFlight.remove(flightKey) }
            do {
                let (data, _) = try await URLSession.shared.data(for: StockService.request(components.url!))
                let decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
                guard let result = decoded.chart.result?.first else {
                    errors[symbol] = decoded.chart.error?.description ?? "Unknown symbol"
                    return
                }
                let closes = (result.indicators.quote.first?.close ?? []).compactMap { $0 }
                quotes[symbol] = Quote(
                    symbol: symbol,
                    name: result.meta.shortName ?? result.meta.longName ?? symbol,
                    price: result.meta.regularMarketPrice,
                    previousClose: result.meta.chartPreviousClose ?? result.meta.previousClose ?? closes.first ?? result.meta.regularMarketPrice,
                    currency: result.meta.currency ?? "USD",
                    history: closes,
                    range: range,
                    fetchedAt: Date()
                )
                errors[symbol] = nil
            } catch {
                errors[symbol] = "Could not load quote."
            }
        }
    }

    func search(_ query: String) async -> [SearchResult] {
        var components = URLComponents(string: "https://query2.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [.init(name: "q", value: query), .init(name: "quotesCount", value: "8"), .init(name: "newsCount", value: "0")]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(for: StockService.request(url)),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return [] }
        return decoded.quotes.compactMap { quote in
            guard let symbol = quote.symbol else { return nil }
            return SearchResult(symbol: symbol, name: quote.shortname ?? quote.longname ?? symbol)
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 DockShift", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func formatPrice(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private struct ChartResponse: Decodable {
        struct Chart: Decodable {
            var result: [Result]?
            var error: ChartError?
        }
        struct ChartError: Decodable { var description: String? }
        struct Result: Decodable {
            var meta: Meta
            var indicators: Indicators
        }
        struct Meta: Decodable {
            var currency: String?
            var regularMarketPrice: Double
            var chartPreviousClose: Double?
            var previousClose: Double?
            var shortName: String?
            var longName: String?
        }
        struct Indicators: Decodable { var quote: [QuoteSeries] }
        struct QuoteSeries: Decodable { var close: [Double?]? }
        var chart: Chart
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            var symbol: String?
            var shortname: String?
            var longname: String?
        }
        var quotes: [Item]
    }
}

// MARK: - Stock tile

struct StockTile: View {
    @ObservedObject private var service = StockService.shared
    let context: WidgetContext
    @State private var showDetails = false

    private var symbol: String { context.setting("symbol", default: "AAPL").uppercased() }
    private var range: String { context.setting("range", default: "1d") }

    private var quote: StockService.Quote? {
        if context.isPreview {
            return .init(symbol: "AAPL", name: "Apple", price: 333.08, previousClose: 332.28, currency: "USD",
                         history: [330, 331, 330.5, 332, 331.5, 333, 332.5, 334, 333.08], range: "1d", fetchedAt: Date())
        }
        return service.quote(for: symbol, range: range)
    }

    var body: some View {
        HStack(spacing: context.iconSize * 0.14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(symbol).font(context.smallFont.weight(.semibold)).foregroundStyle(.secondary)
                Text(quote.map { StockService.formatPrice($0.price) } ?? "—").font(context.valueFont).monospacedDigit()
                Text(changeText).font(context.smallFont.weight(.medium)).foregroundStyle(changeColor)
            }
            .lineLimit(1)
            if let history = quote?.history, history.count > 1 {
                Sparkline(values: history, color: changeColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: context.iconSize * 0.55)
            }
        }
        .padding(.horizontal, context.iconSize * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { showDetails.toggle() } }
        .popover(isPresented: $showDetails) { StockPopout(context: context, symbol: symbol) }
    }

    private var changeText: String {
        guard let quote else { return service.errors[symbol] ?? "Loading" }
        return String(format: "%@%.2f%%", quote.change >= 0 ? "+" : "", quote.changePercent)
    }

    private var changeColor: Color {
        guard let quote else { return .secondary }
        return quote.change >= 0 ? .green : .red
    }
}

private struct StockPopout: View {
    @ObservedObject private var service = StockService.shared
    let context: WidgetContext
    let symbol: String
    @State private var range: String

    init(context: WidgetContext, symbol: String) {
        self.context = context
        self.symbol = symbol
        _range = State(initialValue: context.setting("range", default: "1d"))
    }

    var body: some View {
        let quote = service.quote(for: symbol, range: range)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(quote?.name ?? symbol).font(.headline)
                    Text(symbol).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { service.refresh(symbol, range: range) }.controlSize(.small)
            }
            if let quote {
                HStack(alignment: .firstTextBaseline) {
                    Text(StockService.formatPrice(quote.price)).font(.title2.bold()).monospacedDigit()
                    Text(String(format: "%@%.2f (%.2f%%)", quote.change >= 0 ? "+" : "", quote.change, quote.changePercent))
                        .foregroundStyle(quote.change >= 0 ? .green : .red)
                    Text(quote.currency).font(.caption).foregroundStyle(.secondary)
                }
                Sparkline(values: quote.history, color: quote.change >= 0 ? .green : .red).frame(height: 80)
            } else {
                Text(service.errors[symbol] ?? "Loading…").foregroundStyle(.secondary)
            }
            Picker("Range", selection: $range) {
                ForEach(StockService.ranges, id: \.id) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: range) { newValue in context.set("range", newValue) }
            Text("Data from Yahoo Finance, delayed.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }
}

// MARK: - Watchlist

struct WatchlistTile: View {
    @ObservedObject private var service = StockService.shared
    let context: WidgetContext

    private var symbols: [String] {
        context.setting("symbols", default: "AAPL,MSFT,NVDA").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(spacing: context.iconSize * 0.2) {
            ForEach(symbols.prefix(context.isVertical ? 2 : 3), id: \.self) { symbol in
                let quote: StockService.Quote? = context.isPreview
                    ? previewQuote(symbol)
                    : service.quote(for: symbol)
                VStack(alignment: .center, spacing: 0) {
                    Text(symbol).font(context.smallFont.weight(.semibold)).foregroundStyle(.secondary)
                    Text(quote.map { StockService.formatPrice($0.price) } ?? "—").font(context.valueFont).monospacedDigit()
                    Text(quote.map { String(format: "%@%.2f%%", $0.change >= 0 ? "+" : "", $0.changePercent) } ?? "")
                        .font(context.smallFont.weight(.medium))
                        .foregroundStyle((quote?.change ?? 0) >= 0 ? .green : .red)
                }
                .lineLimit(1)
            }
        }
        .padding(.horizontal, context.iconSize * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewQuote(_ symbol: String) -> StockService.Quote {
        let samples: [String: (Double, Double)] = ["AAPL": (333.08, 332.28), "MSFT": (505.41, 495.6), "NVDA": (210.96, 218.3)]
        let (price, previous) = samples[symbol] ?? (100, 99)
        return .init(symbol: symbol, name: symbol, price: price, previousClose: previous, currency: "USD", history: [], range: "1d", fetchedAt: Date())
    }
}

// MARK: - Config

struct StockConfig: View {
    @ObservedObject private var service = StockService.shared
    let context: WidgetContext
    @State private var query = ""
    @State private var results: [StockService.SearchResult] = []

    private var isWatchlist: Bool { context.instance.type == .watchlist }

    private var symbols: [String] {
        context.setting("symbols", default: "AAPL,MSFT,NVDA").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isWatchlist ? "Watchlist" : "Stock").font(.headline)
            if isWatchlist {
                ForEach(symbols, id: \.self) { symbol in
                    HStack {
                        Text(symbol)
                        Spacer()
                        Button {
                            context.set("symbols", symbols.filter { $0 != symbol }.joined(separator: ","))
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Showing \(context.setting("symbol", default: "AAPL").uppercased())").foregroundStyle(.secondary)
            }
            HStack {
                TextField("Search ticker or company", text: $query).onSubmit(search)
                Button("Search", action: search).disabled(query.isEmpty)
            }
            ForEach(results) { result in
                Button {
                    if isWatchlist {
                        context.set("symbols", (symbols + [result.symbol]).joined(separator: ","))
                    } else {
                        context.set("symbol", result.symbol)
                    }
                    results = []
                    query = ""
                } label: {
                    HStack {
                        Text(result.symbol).bold()
                        Text(result.name).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        Task { results = await service.search(text) }
    }
}
