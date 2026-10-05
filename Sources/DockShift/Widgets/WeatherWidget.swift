import Combine
import CoreLocation
import SwiftUI

/// Forecasts from Open-Meteo (no API key) cached per location.
@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    struct Place: Equatable {
        var name: String
        var latitude: Double
        var longitude: Double

        var key: String { String(format: "%.3f,%.3f", latitude, longitude) }
    }

    struct Hour: Identifiable {
        var id: Date { time }
        var time: Date
        var temperature: Double
        var code: Int
    }

    struct Forecast {
        var temperature: Double
        var code: Int
        var isDay: Bool
        var hours: [Hour]
        var fetchedAt: Date
    }

    @Published private(set) var forecasts: [String: Forecast] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var currentLocation: Place?
    @Published private(set) var locationDenied = false

    private let locationManager = CLLocationManager()
    private var inFlight = Set<String>()

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func forecast(for place: Place) -> Forecast? {
        if let cached = forecasts[place.key], Date().timeIntervalSince(cached.fetchedAt) < 15 * 60 {
            return cached
        }
        fetch(place)
        return forecasts[place.key]
    }

    func refresh(_ place: Place) {
        forecasts[place.key] = nil
        fetch(place)
    }

    private func fetch(_ place: Place) {
        let key = place.key
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "forecast_hours", value: "12"),
            .init(name: "timezone", value: "auto"),
        ]
        Task {
            defer { inFlight.remove(key) }
            do {
                let (data, _) = try await URLSession.shared.data(from: components.url!)
                let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                let local = DateFormatter()
                local.dateFormat = "yyyy-MM-dd'T'HH:mm"
                local.timeZone = TimeZone(identifier: decoded.timezone) ?? .current
                let hours = zip(zip(decoded.hourly.time, decoded.hourly.temperature_2m), decoded.hourly.weather_code).compactMap { pair, code -> Hour? in
                    guard let date = local.date(from: pair.0) else { return nil }
                    return Hour(time: date, temperature: pair.1, code: code)
                }
                forecasts[key] = Forecast(
                    temperature: decoded.current.temperature_2m,
                    code: decoded.current.weather_code,
                    isDay: decoded.current.is_day == 1,
                    hours: hours.filter { $0.time > Date() },
                    fetchedAt: Date()
                )
                errors[key] = nil
            } catch {
                errors[key] = "Could not load the forecast."
            }
        }
    }

    // MARK: Search

    func search(_ query: String) async -> [Place] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "6")]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(GeocodingResponse.self, from: data)
        else { return [] }
        return (decoded.results ?? []).map { result in
            let region = [result.admin1, result.country].compactMap { $0 }.joined(separator: ", ")
            return Place(name: region.isEmpty ? result.name : "\(result.name), \(region)", latitude: result.latitude, longitude: result.longitude)
        }
    }

    // MARK: Location

    func requestLocation() {
        locationDenied = false
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let name = placemarks?.first?.locality ?? placemarks?.first?.name ?? "Current location"
            let place = Place(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            Task { @MainActor in self.currentLocation = place }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.locationDenied = true }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            Task { @MainActor in self.locationDenied = true }
        }
    }

    // MARK: Decoding

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable { var temperature_2m: Double; var weather_code: Int; var is_day: Int }
        struct Hourly: Decodable { var time: [String]; var temperature_2m: [Double]; var weather_code: [Int] }
        var timezone: String
        var current: Current
        var hourly: Hourly
    }

    private struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            var name: String
            var latitude: Double
            var longitude: Double
            var country: String?
            var admin1: String?
        }
        var results: [Result]?
    }
}

/// WMO weather codes to symbols, descriptions and colors.
enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm, hail"
        default: return "Cloudy"
        }
    }

    static func gradient(_ code: Int, isDay: Bool) -> [Color] {
        if !isDay { return [Color(red: 0.15, green: 0.18, blue: 0.35), Color(red: 0.05, green: 0.07, blue: 0.18)] }
        switch code {
        case 0, 1: return [Color(red: 0.35, green: 0.65, blue: 0.98), Color(red: 0.15, green: 0.45, blue: 0.9)]
        case 2, 3, 45, 48: return [Color(red: 0.55, green: 0.62, blue: 0.72), Color(red: 0.35, green: 0.42, blue: 0.52)]
        case 71, 73, 75, 77, 85, 86: return [Color(red: 0.75, green: 0.82, blue: 0.9), Color(red: 0.5, green: 0.6, blue: 0.72)]
        case 95, 96, 99: return [Color(red: 0.3, green: 0.3, blue: 0.42), Color(red: 0.15, green: 0.15, blue: 0.25)]
        default: return [Color(red: 0.4, green: 0.5, blue: 0.65), Color(red: 0.25, green: 0.33, blue: 0.48)]
        }
    }
}

// MARK: - Tile

struct WeatherTile: View {
    @ObservedObject private var service = WeatherService.shared
    let context: WidgetContext
    @State private var showDetails = false

    private var useFahrenheit: Bool { context.setting("units", default: "c") == "f" }
    private var themed: Bool { context.setting("background", default: "themed") == "themed" }
    private var hourCount: Int { min(6, max(1, Int(context.setting("hours", default: "3")) ?? 3)) }

    private var place: WeatherService.Place? {
        if context.setting("useLocation") == "true" { return service.currentLocation }
        guard let lat = Double(context.setting("lat", default: "")), let lon = Double(context.setting("lon", default: "")) else { return nil }
        return .init(name: context.setting("name", default: "Location"), latitude: lat, longitude: lon)
    }

    private var forecast: WeatherService.Forecast? {
        if context.isPreview {
            let now = Date()
            return .init(temperature: 18, code: 2, isDay: true, hours: (1...3).map {
                .init(time: now.addingTimeInterval(Double($0) * 3600), temperature: 17 + Double($0), code: 2)
            }, fetchedAt: now)
        }
        return place.flatMap { service.forecast(for: $0) }
    }

    private func degrees(_ celsius: Double) -> String {
        let value = useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    var body: some View {
        let isDay = forecast?.isDay ?? true
        let code = forecast?.code ?? 3
        HStack(spacing: context.iconSize * 0.14) {
            Image(systemName: WeatherCode.symbol(code, isDay: isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: context.iconSize * 0.4))
            VStack(alignment: .leading, spacing: 0) {
                Text(forecast.map { degrees($0.temperature) } ?? "--°")
                    .font(context.valueFont)
                Text(caption)
                    .font(context.captionFont)
                    .foregroundStyle(themed ? .white.opacity(0.8) : .secondary)
            }
            .lineLimit(1)
            if context.variant == "hourly", let hours = forecast?.hours.prefix(context.isVertical ? min(hourCount, 3) : hourCount), !hours.isEmpty {
                Spacer(minLength: 4)
                ForEach(Array(hours)) { hour in
                    VStack(spacing: 1) {
                        Text(hourLabel(hour.time)).font(context.smallFont).foregroundStyle(themed ? .white.opacity(0.8) : .secondary)
                        Image(systemName: WeatherCode.symbol(hour.code, isDay: isDay)).symbolRenderingMode(.multicolor).font(.system(size: context.iconSize * 0.18))
                        Text(degrees(hour.temperature)).font(context.smallFont.weight(.semibold))
                    }
                }
            }
        }
        .foregroundStyle(themed ? .white : .primary)
        .padding(.horizontal, context.iconSize * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            themed
                ? AnyView(LinearGradient(colors: WeatherCode.gradient(code, isDay: isDay), startPoint: .top, endPoint: .bottom))
                : AnyView(Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { showDetails.toggle() } }
        .popover(isPresented: $showDetails) { WeatherPopout(context: context, place: place) }
    }

    private var caption: String {
        if context.isPreview { return context.variant == "conditions" ? "Partly cloudy" : "Oslo" }
        guard let place else { return service.locationDenied ? "Location denied" : "Set a location" }
        if let key = Optional(place.key), let error = service.errors[key], forecast == nil { return error }
        return context.variant == "conditions" ? WeatherCode.description(forecast?.code ?? 3) : place.name
    }

    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date).replacingOccurrences(of: " ", with: "")
    }
}

private struct WeatherPopout: View {
    @ObservedObject private var service = WeatherService.shared
    let context: WidgetContext
    let place: WeatherService.Place?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(place?.name ?? "Weather").font(.headline)
                Spacer()
                if let place {
                    Button("Refresh") { service.refresh(place) }.controlSize(.small)
                }
            }
            if let place, let forecast = service.forecast(for: place) {
                Text("\(WeatherCode.description(forecast.code)) · \(Int(forecast.temperature.rounded()))°C").foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(forecast.hours) { hour in
                            VStack(spacing: 3) {
                                Text(TimeFormat.clock(hour.time)).font(.caption2).foregroundStyle(.secondary)
                                Image(systemName: WeatherCode.symbol(hour.code, isDay: forecast.isDay)).symbolRenderingMode(.multicolor)
                                Text("\(Int(hour.temperature.rounded()))°").font(.caption)
                            }
                        }
                    }
                }
                Text("Updated \(TimeFormat.clock(forecast.fetchedAt)) · Open-Meteo").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(place == nil ? "Right-click the widget to choose a location." : "Loading forecast…").foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct WeatherConfig: View {
    @ObservedObject private var service = WeatherService.shared
    let context: WidgetContext
    @State private var query = ""
    @State private var results: [WeatherService.Place] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weather").font(.headline)
            HStack {
                TextField("Search for a city", text: $query)
                    .onSubmit(search)
                Button("Search", action: search).disabled(query.isEmpty)
            }
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(results, id: \.key) { place in
                        Button {
                            context.set(["name": place.name, "lat": String(place.latitude), "lon": String(place.longitude), "useLocation": nil])
                            results = []
                            query = ""
                        } label: {
                            Text(place.name).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }
            }
            Button(context.setting("useLocation") == "true" ? "Using current location" : "Use current location") {
                service.requestLocation()
                context.set(["useLocation": "true"])
            }
            if service.locationDenied {
                Text("Location access was denied. Search for a city instead.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Units", selection: Binding(get: { context.setting("units", default: "c") }, set: { context.set("units", $0) })) {
                Text("°C").tag("c")
                Text("°F").tag("f")
            }
            .pickerStyle(.segmented)
            Picker("Background", selection: Binding(get: { context.setting("background", default: "themed") }, set: { context.set("background", $0) })) {
                Text("Themed").tag("themed")
                Text("Translucent").tag("plain")
            }
            .pickerStyle(.segmented)
            if context.variant == "hourly" {
                Stepper("Hours shown: \(context.setting("hours", default: "3"))", value: Binding(
                    get: { Int(context.setting("hours", default: "3")) ?? 3 },
                    set: { context.set("hours", String(min(6, max(1, $0)))) }
                ), in: 1...6)
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
