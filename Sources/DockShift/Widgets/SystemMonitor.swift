import Combine
import Darwin
import Foundation
import IOKit.ps

/// Samples CPU, memory and network every two seconds while a widget is showing.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var coreUsage: [Double] = []
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var memoryTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var memoryPressure: String = "Normal"
    @Published private(set) var swapUsed: Double = 0
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []

    private var timer: AnyCancellable?
    private var interest = 0
    private var previousTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
    private var previousBytes: (rx: UInt64, tx: UInt64, at: Date)?

    private init() {}

    func retain() {
        interest += 1
        if timer == nil {
            sample()
            timer = Timer.publish(every: 2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.sample() }
        }
    }

    func release() {
        interest = max(0, interest - 1)
        if interest == 0 { timer = nil }
    }

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
    }

    private func sampleCPU() {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var ticks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            ticks.append((
                UInt32(info[base + Int(CPU_STATE_USER)]),
                UInt32(info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(info[base + Int(CPU_STATE_IDLE)]),
                UInt32(info[base + Int(CPU_STATE_NICE)])
            ))
        }
        if previousTicks.count == ticks.count {
            var usages: [Double] = []
            for (now, before) in zip(ticks, previousTicks) {
                let busy = Double((now.user &- before.user) &+ (now.system &- before.system) &+ (now.nice &- before.nice))
                let idle = Double(now.idle &- before.idle)
                let total = busy + idle
                usages.append(total > 0 ? busy / total : 0)
            }
            coreUsage = usages
            cpuUsage = usages.isEmpty ? 0 : usages.reduce(0, +) / Double(usages.count)
        }
        previousTicks = ticks
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        memoryUsed = used
        let fraction = memoryTotal > 0 ? used / memoryTotal : 0
        memoryPressure = fraction > 0.9 ? "Critical" : (fraction > 0.75 ? "Warning" : "Normal")

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsed = Double(swap.xsu_used)
        }
    }

    private func sampleNetwork() {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            if interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               name.hasPrefix("en") || name.hasPrefix("pdp"),
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += UInt64(data.pointee.ifi_ibytes)
                tx += UInt64(data.pointee.ifi_obytes)
            }
            pointer = interface.ifa_next
        }
        let now = Date()
        if let previous = previousBytes {
            let seconds = now.timeIntervalSince(previous.at)
            if seconds > 0 {
                downloadRate = Double(rx >= previous.rx ? rx - previous.rx : 0) / seconds
                uploadRate = Double(tx >= previous.tx ? tx - previous.tx : 0) / seconds
                downloadHistory = Array((downloadHistory + [downloadRate]).suffix(30))
                uploadHistory = Array((uploadHistory + [uploadRate]).suffix(30))
            }
        }
        previousBytes = (rx, tx, now)
    }

    static func formatRate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSecond
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        return index == 0 ? "\(Int(value)) \(units[0])" : String(format: "%.0f %@", value, units[index])
    }

    static func formatBytes(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

/// Battery levels for the Mac and Bluetooth input devices.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    struct Device: Identifiable {
        var id: String
        var name: String
        var symbol: String
        var percent: Int
        var isCharging: Bool
    }

    @Published private(set) var devices: [Device] = []
    private var timer: AnyCancellable?
    private var interest = 0

    private init() {}

    func retain() {
        interest += 1
        if timer == nil {
            sample()
            timer = Timer.publish(every: 60, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.sample() }
        }
    }

    func release() {
        interest = max(0, interest - 1)
        if interest == 0 { timer = nil }
    }

    private func sample() {
        var found: [Device] = []

        // Internal battery via IOKit power sources.
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                      let capacity = description[kIOPSCurrentCapacityKey] as? Int else { continue }
                let charging = description[kIOPSIsChargingKey] as? Bool ?? false
                found.append(Device(id: "internal", name: "Mac", symbol: "laptopcomputer", percent: capacity, isCharging: charging))
            }
        }

        // Bluetooth keyboards, mice and trackpads report through the HID registry.
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dictionary = properties?.takeRetainedValue() as? [String: Any],
                   let percent = dictionary["BatteryPercent"] as? Int {
                    let name = dictionary["Product"] as? String ?? "Device"
                    let lower = name.lowercased()
                    let symbol = lower.contains("keyboard") ? "keyboard" : (lower.contains("trackpad") ? "rectangle.and.hand.point.up.left" : (lower.contains("mouse") ? "computermouse" : "dot.radiowaves.left.and.right"))
                    found.append(Device(id: name + String(service), name: name, symbol: symbol, percent: percent, isCharging: false))
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        devices = found
    }
}
