import Carbon

/// A system-wide shortcut through Carbon's RegisterEventHotKey, which needs no permission. Carbon calls back on the main
/// thread. If another app already owns the shortcut, registering fails quietly and the menu still works.
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// ⌃⌥L
    static func laser(_ action: @escaping () -> Void) -> Hotkey {
        Hotkey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey), action: action)
    }

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            Unmanaged<Hotkey>.fromOpaque(data).takeUnretainedValue().action()
            return OSStatus(noErr)
        }, 1, &spec, me, &handler)
        // 'PANI'
        let id = EventHotKeyID(signature: OSType(0x5041_4E49), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
