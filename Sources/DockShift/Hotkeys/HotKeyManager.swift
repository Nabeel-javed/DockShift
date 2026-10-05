import AppKit
import Carbon

/// Registers system-wide hotkeys with Carbon and maps them back to profiles.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTrigger: (@MainActor (UUID) -> Void)?

    private var registered: [UInt32: (ref: EventHotKeyRef, profileID: UUID)] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private static let signature = OSType(0x4453_4846) // "DSHF"

    private init() {
        installHandler()
    }

    /// Re-registers every shortcut so the set matches `profiles`.
    func sync(profiles: [DockProfile]) {
        unregisterAll()
        for profile in profiles {
            if let combo = profile.shortcut {
                register(combo, for: profile.id)
            }
        }
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handle(id: hotKeyID.id)
            return noErr
        }, 1, &spec, userData, &handlerRef)
    }

    private func register(_ combo: KeyCombo, for profileID: UUID) {
        let id = EventHotKeyID(signature: HotKeyManager.signature, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return }
        registered[nextID] = (ref, profileID)
        nextID += 1
    }

    private func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    private func handle(id: UInt32) {
        guard let entry = registered[id], let handler = onTrigger else { return }
        let profileID = entry.profileID
        Task { @MainActor in handler(profileID) }
    }
}
