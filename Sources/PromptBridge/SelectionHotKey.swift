import AppKit
import Carbon
import DraftCore

extension TranslationShortcut {
    @MainActor var displayName: String {
        var result = ""
        for (flag, symbol) in [(controlKey,"⌃"), (optionKey,"⌥"), (shiftKey,"⇧"), (cmdKey,"⌘")] where modifiers & UInt32(flag) != 0 {
            result += symbol
        }
        let label = keyLabel() ?? "键位 \(keyCode)"
        let upper = label.uppercased()
        let keypad = (82...89).contains(keyCode) || keyCode == 91 || keyCode == 92
        return result + (keypad ? "小键盘 " : "") + (upper.count == 1 ? upper : label)
    }

    @MainActor func keyLabel(shifted: Bool = false) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
            var dead: UInt32 = 0
            var buffer = [UniChar](repeating: 0, count: 8)
            var length = 0
            if UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), shifted ? UInt32(shiftKey >> 8) : 0, UInt32(LMGetKbdType()),
                              UInt32(kUCKeyTranslateNoDeadKeysMask), &dead, buffer.count, &length, &buffer) == noErr, length > 0 {
                return String(utf16CodeUnits: buffer, count: length)
            }
        }
        return nil
    }
}

struct ShortcutRegistrationError: LocalizedError {
    let shortcut: TranslationShortcut
    let status: OSStatus
    var errorDescription: String? {
        if status == OSStatus(eventHotKeyExistsErr) { return "该组合键已被占用，请选择其他组合。" }
        return "快捷键注册失败（系统状态 \(status)），请尝试其他组合。"
    }
}

@MainActor final class SelectionHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var activeID: UInt32 = 0
    private var nextID: UInt32 = 1
    private let action: () -> Void
    var recordingAction: ((TranslationShortcut) -> Void)?
    private(set) var active: TranslationShortcut?

    init(action: @escaping () -> Void) { self.action = action }

    func apply(_ shortcut: TranslationShortcut, persist: () throws -> Void) throws {
        guard active != shortcut else { try persist(); return }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout.size(ofValue: id), nil, &id) == noErr,
                      id.signature == 0x50425247 else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    let owner = Unmanaged<SelectionHotKey>.fromOpaque(context).takeUnretainedValue()
                    guard id.id == owner.activeID, let active = owner.active else { return }
                    if let capture = owner.recordingAction { capture(active) } else { owner.action() }
                }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw ShortcutRegistrationError(shortcut: shortcut, status: status) }
        }
        let id = nextID
        nextID &+= 1
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x50425247, id: id),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &candidate)
        guard status == noErr, let candidate else { throw ShortcutRegistrationError(shortcut: shortcut, status: status) }
        do { try persist() } catch { UnregisterEventHotKey(candidate); throw error }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = candidate
        activeID = id
        active = shortcut
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        active = nil
    }
}
