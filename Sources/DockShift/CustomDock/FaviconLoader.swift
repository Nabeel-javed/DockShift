import AppKit
import Combine

/// Fetches and caches website icons for link tiles.
@MainActor
final class FaviconLoader: ObservableObject {
    static let shared = FaviconLoader()

    @Published private(set) var icons: [String: NSImage] = [:]
    private var inFlight = Set<String>()
    private let cacheDirectory: URL

    private init() {
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DockShift/Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func icon(for link: LinkReference) -> NSImage? {
        guard let host = link.url?.host else { return nil }
        if let cached = icons[host] { return cached }
        if let disk = NSImage(contentsOf: cacheDirectory.appendingPathComponent(host + ".png")) {
            icons[host] = disk
            return disk
        }
        fetch(host: host)
        return nil
    }

    private func fetch(host: String) {
        guard !inFlight.contains(host) else { return }
        inFlight.insert(host)
        let candidates = [
            "https://\(host)/apple-touch-icon.png",
            "https://\(host)/favicon.ico",
        ].compactMap(URL.init(string:))
        let file = cacheDirectory.appendingPathComponent(host + ".png")

        Task {
            for url in candidates {
                if let (data, response) = try? await URLSession.shared.data(from: url),
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   let image = NSImage(data: data), image.isValid {
                    icons[host] = image
                    if let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: file)
                    }
                    break
                }
            }
            inFlight.remove(host)
        }
    }
}
