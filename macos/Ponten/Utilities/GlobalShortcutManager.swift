import AppKit
import Carbon

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()
    
    private var hotKeyRef: EventHotKeyRef?
    var action: (() -> Void)?
    
    private init() {
        guard !E2EMode.isEnabled else { return }
        setupHotKey()
    }
    
    private func setupHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if status == noErr && hotKeyID.signature == OSType(1) {
                DispatchQueue.main.async {
                    GlobalShortcutManager.shared.action?()
                }
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        
        // Initialize from UserDefaults
        let saved = UserDefaults.standard.integer(forKey: "GlobalShortcut")
        updateShortcut(ShortcutChoice(rawValue: saved) ?? .optCmdS)
    }
    
    func updateShortcut(_ choice: ShortcutChoice) {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        
        let keyCode: UInt32 = 0x01 // S
        var modifiers: UInt32 = 0
        switch choice {
        case .optCmdS: modifiers = UInt32(cmdKey | optionKey)
        case .ctrlCmdS: modifiers = UInt32(cmdKey | controlKey)
        case .shiftCmdS: modifiers = UInt32(cmdKey | shiftKey)
        }
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(1)
        hotKeyID.id = UInt32(1)
        
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
