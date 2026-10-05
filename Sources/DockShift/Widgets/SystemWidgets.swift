import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Battery

struct BatteryTile: View {
    @ObservedObject private var monitor = BatteryMonitor.shared
    let context: WidgetContext

    private var devices: [BatteryMonitor.Device] {
        if context.isPreview {
            return [
                .init(id: "mac", name: "Mac", symbol: "laptopcomputer", percent: 76, isCharging: false),
                .init(id: "pods", name: "AirPods", symbol: "airpodspro", percent: 85, isCharging: false),
                .init(id: "phone", name: "iPhone", symbol: "iphone", percent: 32, isCharging: true),
                .init(id: "kb", name: "Keyboard", symbol: "keyboard", percent: 92, isCharging: false),
            ]
        }
        return monitor.devices
    }

    var body: some View {
        HStack(spacing: context.iconSize * 0.16) {
            if devices.isEmpty {
                Text("No batteries found").font(context.captionFont).foregroundStyle(.secondary)
            }
            ForEach(devices.prefix(4)) { device in
                VStack(spacing: 2) {
                    ZStack {
                        RingView(progress: Double(device.percent) / 100, lineWidth: context.iconSize * 0.06, color: color(for: device.percent))
                        Image(systemName: device.symbol)
                            .font(.system(size: context.iconSize * 0.2))
                        if device.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: context.iconSize * 0.14))
                                .foregroundStyle(.yellow)
                                .offset(x: context.iconSize * 0.2, y: context.iconSize * 0.2)
                        }
                    }
                    .frame(width: context.iconSize * 0.5, height: context.iconSize * 0.5)
                    if context.variant != "icon" {
                        Text("\(device.percent)%")
                            .font(context.smallFont)
                            .foregroundStyle(context.variant == "ring" ? .primary : .secondary)
                            .monospacedDigit()
                    }
                }
                .help(device.name)
            }
        }
        .padding(.horizontal, context.iconSize * 0.14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if !context.isPreview { monitor.retain() } }
        .onDisappear { if !context.isPreview { monitor.release() } }
    }

    private func color(for percent: Int) -> Color {
        percent <= 20 ? .red : (percent <= 40 ? .orange : .green)
    }
}

// MARK: - System activity

struct SystemActivityTile: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    let context: WidgetContext
    @State private var showDetails = false

    private var cpu: Double { context.isPreview ? 0.24 : monitor.cpuUsage }
    private var memory: Double { context.isPreview ? 0.63 : monitor.memoryFraction }

    var body: some View {
        Group {
            switch context.variant {
            case "rings":
                HStack(spacing: context.iconSize * 0.2) {
                    ringStat(value: cpu, label: "CPU", color: .purple)
                    ringStat(value: memory, label: "Memory", color: .blue)
                }
            case "bars":
                VStack(alignment: .leading, spacing: context.iconSize * 0.06) {
                    barStat(value: cpu, label: "CPU", color: .purple)
                    barStat(value: memory, label: "Memory", color: .blue)
                }
            default:
                HStack(spacing: context.iconSize * 0.24) {
                    numberStat(value: cpu, label: "CPU", color: .purple)
                    numberStat(value: memory, label: "Memory", color: .blue)
                }
            }
        }
        .padding(.horizontal, context.iconSize * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if !context.isPreview { showDetails.toggle() } }
        .popover(isPresented: $showDetails) { SystemDetailsPopout() }
        .onAppear { if !context.isPreview { monitor.retain() } }
        .onDisappear { if !context.isPreview { monitor.release() } }
    }

    private func numberStat(value: Double, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Int(value * 100))%").font(context.valueFont).monospacedDigit()
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(context.smallFont).foregroundStyle(.secondary)
            }
        }
    }

    private func ringStat(value: Double, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            ZStack {
                RingView(progress: value, lineWidth: context.iconSize * 0.07, color: color)
                Text("\(Int(value * 100))%").font(.system(size: context.iconSize * 0.14, weight: .semibold)).monospacedDigit()
            }
            .frame(width: context.iconSize * 0.52, height: context.iconSize * 0.52)
            Text(label).font(context.smallFont).foregroundStyle(.secondary)
        }
    }

    private func barStat(value: Double, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(context.smallFont).foregroundStyle(.secondary).frame(width: context.iconSize * 0.7, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule().fill(color).frame(width: proxy.size.width * value)
                }
            }
            .frame(height: context.iconSize * 0.1)
            Text("\(Int(value * 100))%").font(context.smallFont.weight(.semibold)).monospacedDigit().frame(width: context.iconSize * 0.5, alignment: .trailing)
        }
    }
}

private struct SystemDetailsPopout: View {
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System Activity").font(.headline)
            Text("CPU \(Int(monitor.cpuUsage * 100))% across \(monitor.coreUsage.count) cores").font(.callout)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(monitor.coreUsage.enumerated()), id: \.offset) { _, usage in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(usage > 0.8 ? Color.red : Color.purple)
                        .frame(width: 10, height: max(2, 40 * usage))
                }
            }
            .frame(height: 40, alignment: .bottom)
            Divider()
            Text("Memory \(SystemMonitor.formatBytes(monitor.memoryUsed)) of \(SystemMonitor.formatBytes(monitor.memoryTotal))").font(.callout)
            ProgressView(value: monitor.memoryFraction).tint(monitor.memoryPressure == "Normal" ? .blue : .orange)
            HStack {
                Text("Pressure: \(monitor.memoryPressure)")
                Spacer()
                Text("Swap: \(SystemMonitor.formatBytes(monitor.swapUsed))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 280)
    }
}

// MARK: - Network

struct NetworkTile: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    let context: WidgetContext

    private var download: Double { context.isPreview ? 778_000 : monitor.downloadRate }
    private var upload: Double { context.isPreview ? 294_000 : monitor.uploadRate }

    var body: some View {
        HStack(spacing: context.iconSize * 0.16) {
            VStack(alignment: .leading, spacing: 0) {
                rate(download, symbol: "arrow.down", color: .blue)
                rate(upload, symbol: "arrow.up", color: .purple)
            }
            if context.variant == "chart" {
                Sparkline(values: context.isPreview ? [3, 5, 4, 8, 6, 9, 5, 7, 8, 6, 9, 10, 7] : monitor.downloadHistory, color: .blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: context.iconSize * 0.5)
            }
        }
        .padding(.horizontal, context.iconSize * 0.14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if !context.isPreview { monitor.retain() } }
        .onDisappear { if !context.isPreview { monitor.release() } }
    }

    private func rate(_ value: Double, symbol: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: context.iconSize * 0.14, weight: .bold)).foregroundStyle(color)
            Text(SystemMonitor.formatRate(value)).font(context.smallFont.weight(.semibold)).monospacedDigit()
        }
        .lineLimit(1)
    }
}

/// A small line chart of recent values.
struct Sparkline: View {
    let values: [Double]
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 1, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: values.count > 1 ? proxy.size.width * CGFloat(index) / CGFloat(values.count - 1) : 0,
                    y: proxy.size.height * (1 - CGFloat(value / maxValue))
                )
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.15))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

// MARK: - Shortcut

/// Runs an Apple Shortcut through the `shortcuts` command line tool.
struct ShortcutTile: View {
    let context: WidgetContext
    @State private var isRunning = false

    private var name: String { context.setting("name", default: "") }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: context.setting("symbol", default: "square.stack.3d.up.fill"))
                .font(.system(size: context.iconSize * 0.32))
                .foregroundStyle(isRunning ? Color.secondary : Color.accentColor)
            Text(context.isPreview ? "Shazam" : (name.isEmpty ? "Choose a shortcut" : name))
                .font(context.smallFont.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, context.iconSize * 0.1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: run)
    }

    private func run() {
        guard !context.isPreview, !name.isEmpty, !isRunning else { return }
        isRunning = true
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.terminationHandler = { _ in
            Task { @MainActor in isRunning = false }
        }
        do {
            try process.run()
        } catch {
            isRunning = false
        }
    }
}

struct ShortcutConfig: View {
    let context: WidgetContext
    @State private var names: [String] = []

    private static let symbols = ["square.stack.3d.up.fill", "bolt.fill", "wand.and.stars", "camera.fill", "music.note", "doc.text", "message.fill", "house.fill", "moon.fill", "sun.max.fill", "terminal.fill", "gearshape.fill"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shortcut").font(.headline)
                Spacer()
                Button("Refresh", action: load).controlSize(.small)
            }
            if names.isEmpty {
                Text("No shortcuts found. Create one in the Shortcuts app, then refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Shortcut", selection: Binding(
                    get: { context.setting("name") ?? "" },
                    set: { context.set("name", $0.isEmpty ? nil : $0) }
                )) {
                    Text("Choose…").tag("")
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
            }
            Picker("Icon", selection: Binding(
                get: { context.setting("symbol") ?? "square.stack.3d.up.fill" },
                set: { context.set("symbol", $0) }
            )) {
                ForEach(ShortcutConfig.symbols, id: \.self) { Label($0, systemImage: $0).tag($0) }
            }
        }
        .padding(12)
        .onAppear(perform: load)
    }

    private func load() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        names = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

// MARK: - AirDrop

/// Drop files on the tile, or click to pick them, and AirDrop them.
struct AirDropTile: View {
    let context: WidgetContext
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "airplayaudio")
                .font(.system(size: context.iconSize * 0.32))
                .foregroundStyle(.blue)
            Text("AirDrop")
                .font(context.smallFont.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: context.iconSize * 0.22, style: .continuous)
                .fill(Color.blue.opacity(isTargeted ? 0.25 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: chooseFiles)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                share(urls)
            }
            return true
        }
        .contextMenu {
            Button("Choose Files…", action: chooseFiles)
        }
    }

    private func chooseFiles() {
        guard !context.isPreview else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose files to send with AirDrop."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        share(panel.urls)
    }

    private func share(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }
}
