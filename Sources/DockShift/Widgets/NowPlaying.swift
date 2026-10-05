import AppKit
import Combine
import SwiftUI

/// Talks to Spotify and Music through Apple Events. Polls only while one of
/// them is running, so idle cost stays near zero.
@MainActor
final class NowPlayingController: ObservableObject {
    static let shared = NowPlayingController()

    enum Player: String, CaseIterable {
        case spotify = "Spotify"
        case music = "Music"

        var bundleID: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music: return "com.apple.Music"
            }
        }
    }

    struct Track: Equatable {
        var player: Player
        var isPlaying: Bool
        var title: String
        var artist: String
        var position: TimeInterval
        var duration: TimeInterval
        var artworkURL: URL?
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isAnyPlayerRunning = false
    /// Set when macOS denied Automation access; cleared on the next success.
    @Published private(set) var automationDenied = false

    private var timer: AnyCancellable?
    private var artworkURL: URL?
    private var interest = 0

    private init() {}

    /// Tiles call this on appear/disappear so polling only runs when needed.
    func retain() {
        interest += 1
        if timer == nil {
            timer = Timer.publish(every: 2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.poll() }
            poll()
        }
    }

    func release() {
        interest = max(0, interest - 1)
        if interest == 0 {
            timer = nil
        }
    }

    private func runningPlayer() -> Player? {
        for player in Player.allCases where !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty {
            return player
        }
        return nil
    }

    private func poll() {
        guard let player = runningPlayer() else {
            isAnyPlayerRunning = false
            track = nil
            artwork = nil
            return
        }
        isAnyPlayerRunning = true

        let script: String
        switch player {
        case .spotify:
            script = """
            tell application "Spotify"
                if player state is stopped then return "stopped"
                set s to player state as string
                set t to name of current track
                set a to artist of current track
                set p to player position
                set d to (duration of current track) / 1000
                set art to artwork url of current track
                return s & "|" & t & "|" & a & "|" & p & "|" & d & "|" & art
            end tell
            """
        case .music:
            script = """
            tell application "Music"
                if player state is stopped then return "stopped"
                set s to player state as string
                set t to name of current track
                set a to artist of current track
                set p to player position
                set d to duration of current track
                return s & "|" & t & "|" & a & "|" & p & "|" & d & "|"
            end tell
            """
        }

        guard let output = run(script) else { return }
        let parts = output.components(separatedBy: "|")
        guard parts.count >= 5, parts[0] != "stopped" else {
            track = nil
            artwork = nil
            return
        }
        let newTrack = Track(
            player: player,
            isPlaying: parts[0] == "playing",
            title: parts[1],
            artist: parts[2],
            position: Double(parts[3]) ?? 0,
            duration: Double(parts[4]) ?? 0,
            artworkURL: parts.count > 5 ? URL(string: parts[5]) : nil
        )
        track = newTrack
        loadArtwork(newTrack.artworkURL)
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        guard let url else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) {
                if self.artworkURL == url { self.artwork = image }
            }
        }
    }

    @discardableResult
    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -1743: the user denied Automation access for this app.
            automationDenied = (error[NSAppleScript.errorNumber] as? Int) == -1743
            return nil
        }
        automationDenied = false
        return result?.stringValue
    }

    // MARK: Controls

    func playPause() { command("playpause") }
    func nextTrack() { command("next track") }
    func previousTrack() { command("previous track") }

    func skip(by seconds: TimeInterval) {
        guard let track else { return }
        let target = max(0, min(track.duration, track.position + seconds))
        command("set player position to \(target)")
    }

    private func command(_ verb: String) {
        guard let player = track?.player ?? runningPlayer() else { return }
        run("tell application \"\(player.rawValue)\" to \(verb)")
        poll()
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Tile

struct NowPlayingTile: View {
    @ObservedObject private var controller = NowPlayingController.shared
    let context: WidgetContext

    private var skipSeconds: TimeInterval? {
        let value = context.setting("skip", default: "0")
        return value == "0" ? nil : Double(value)
    }

    private var track: NowPlayingController.Track? {
        if context.isPreview {
            return .init(player: .music, isPlaying: true, title: "The Entertainer", artist: "Scott Joplin",
                         position: 0, duration: 306, artworkURL: nil)
        }
        return controller.track
    }

    var body: some View {
        Group {
            if context.variant == "mini" {
                mini
            } else {
                full
            }
        }
        .onAppear { if !context.isPreview { controller.retain() } }
        .onDisappear { if !context.isPreview { controller.release() } }
    }

    private var mini: some View {
        Button {
            if !context.isPreview { controller.playPause() }
        } label: {
            Image(systemName: track?.isPlaying == true ? "pause.fill" : "play.fill")
                .font(.system(size: context.iconSize * 0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(track.map { "\($0.title) – \($0.artist)" } ?? "Now Playing")
    }

    private var full: some View {
        HStack(spacing: context.iconSize * 0.14) {
            artworkView
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track?.title ?? (controller.automationDenied ? "Automation access needed" : "Nothing playing"))
                            .font(context.captionFont.weight(.semibold))
                        Text(track?.artist ?? (controller.isAnyPlayerRunning ? "" : "Open Music or Spotify"))
                            .font(context.smallFont)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    controls
                }
                progress
            }
        }
        .padding(.horizontal, context.iconSize * 0.14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            if controller.automationDenied {
                Button("Open Automation Settings…") { controller.openAutomationSettings() }
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        let side = context.iconSize * 0.62
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.18, style: .continuous).fill(.primary.opacity(0.1))
            if let artwork = controller.artwork, !context.isPreview {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: side * 0.45)).foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: context.iconSize * 0.1) {
            if let skipSeconds {
                controlButton("gobackward.\(Int(skipSeconds))", fallback: "gobackward") { controller.skip(by: -skipSeconds) }
            } else if context.setting("prevNext", default: "true") == "true" {
                controlButton("backward.end.fill") { controller.previousTrack() }
            }
            controlButton(track?.isPlaying == true ? "pause.fill" : "play.fill") { controller.playPause() }
            if let skipSeconds {
                controlButton("goforward.\(Int(skipSeconds))", fallback: "goforward") { controller.skip(by: skipSeconds) }
            } else if context.setting("prevNext", default: "true") == "true" {
                controlButton("forward.end.fill") { controller.nextTrack() }
            }
        }
    }

    private func controlButton(_ symbol: String, fallback: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            if !context.isPreview { action() }
        } label: {
            Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : (fallback ?? symbol))
                .font(.system(size: context.iconSize * 0.2))
                .frame(width: context.iconSize * 0.3, height: context.iconSize * 0.3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        HStack(spacing: 4) {
            Text(TimeFormat.duration(track?.position ?? 0))
            GeometryReader { proxy in
                let fraction = (track?.duration ?? 0) > 0 ? (track?.position ?? 0) / (track?.duration ?? 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.15))
                    Capsule().fill(.primary.opacity(0.7)).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
            Text(TimeFormat.duration(track?.duration ?? 0))
        }
        .font(.system(size: max(7, context.iconSize * 0.12)))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

struct NowPlayingConfig: View {
    let context: WidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Now Playing").font(.headline)
            Toggle("Previous / next buttons", isOn: Binding(
                get: { context.setting("prevNext", default: "true") == "true" },
                set: { context.set("prevNext", $0 ? "true" : "false") }
            ))
            Picker("Skip buttons", selection: Binding(
                get: { context.setting("skip", default: "0") },
                set: { context.set("skip", $0) }
            )) {
                Text("Off").tag("0")
                ForEach(["5", "10", "15", "30", "60"], id: \.self) { Text("\($0) seconds").tag($0) }
            }
            Toggle("Hide when music apps are closed", isOn: Binding(
                get: { context.setting("hideWhenClosed", default: "false") == "true" },
                set: { context.set("hideWhenClosed", $0 ? "true" : "false") }
            ))
            Text("Controls Spotify and Music. macOS asks for Automation access the first time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
