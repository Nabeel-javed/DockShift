import Combine
import Foundation

/// Other apps' "Open at Login" setting, read and changed through System Events
/// (the same permission the Dock's slide already uses). Cached, because
/// asking System Events takes a moment and menus are built often.
@MainActor
final class LoginItems: ObservableObject {
    static let shared = LoginItems()

    @Published private(set) var paths: Set<String> = []

    private init() {
        refresh()
    }

    func contains(_ url: URL) -> Bool {
        paths.contains(url.standardizedFileURL.path)
    }

    func set(_ url: URL, enabled: Bool) {
        let path = url.standardizedFileURL.path
        let name = url.deletingPathExtension().lastPathComponent
        let script = enabled
            ? "tell application \"System Events\" to make login item at end with properties {path:\(quoted(path)), hidden:false}"
            : "tell application \"System Events\" to delete (every login item whose path is \(quoted(path)) or name is \(quoted(name)))"
        if enabled { paths.insert(path) } else { paths.remove(path) }
        Task.detached {
            _ = LoginItems.run(script)
            await MainActor.run { LoginItems.shared.refresh() }
        }
    }

    func refresh() {
        Task.detached {
            let output = LoginItems.run("tell application \"System Events\" to get the path of every login item") ?? ""
            let found = Set(output.components(separatedBy: ", ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path })
            await MainActor.run { LoginItems.shared.paths = found }
        }
    }

    private func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    nonisolated private static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
