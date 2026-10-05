import AppKit
import SwiftUI

/// A button that records the next key combination pressed.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(isRecording ? "Press keys…" : (combo?.display ?? "Record Shortcut"))
                    .frame(minWidth: 110)
            }
            .foregroundStyle(isRecording ? Color.accentColor : Color.primary)

            if combo != nil && !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
                stop()
                return nil
            }
            guard let recorded = KeyCombo(event: event) else {
                NSSound.beep()
                return nil
            }
            combo = recorded
            stop()
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
