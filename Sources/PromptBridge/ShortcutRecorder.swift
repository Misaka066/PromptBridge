import AppKit
import Carbon
import DraftCore
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: TranslationShortcut
    let settings: TranslationSettings

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        button.setAccessibilityLabel("录入整框翻译快捷键")
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.settings = settings
        button.accept = { shortcut = $0 }
        button.savedTitle = shortcut.displayName
        if !button.recording { button.title = button.savedTitle }
    }

    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) { button.finish() }

    final class RecorderButton: NSButton {
        weak var settings: TranslationSettings?
        var accept: ((TranslationShortcut) -> Void)?
        var savedTitle = ""
        var recording = false
        override var acceptsFirstResponder: Bool { true }

        @objc func beginRecording() {
            guard window?.makeFirstResponder(self) == true else { return }
            recording = true
            title = "按下组合键（Esc 取消）"
            settings?.hotKey?.recordingAction = { [weak self] in self?.choose($0) }
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(finish), name: NSWindow.didResignKeyNotification, object: window)
        }

        private func choose(_ shortcut: TranslationShortcut) {
            accept?(shortcut)
            savedTitle = shortcut.displayName
            finish()
        }

        @objc func finish() {
            guard recording else { return }
            recording = false
            settings?.hotKey?.recordingAction = nil
            title = savedTitle
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        }

        override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { finish(); return }
            if event.keyCode == 48 { finish(); super.keyDown(with: event); return }
            var flags: UInt32 = 0
            for (modifier, bit): (NSEvent.ModifierFlags, Int) in [(.control,controlKey), (.option,optionKey), (.command,cmdKey), (.shift,shiftKey)] where event.modifierFlags.contains(modifier) {
                flags |= UInt32(bit)
            }
            let value = TranslationShortcut(keyCode: UInt32(event.keyCode), modifiers: flags)
            let label = value.keyLabel() ?? ""
            let shifted = value.keyLabel(shifted: true) ?? ""
            let letterOrDigit = label.count == 1 && label.allSatisfy { $0.isLetter || $0.isNumber }
            let shiftedDigit = shifted.count == 1 && shifted.allSatisfy { $0.isNumber }
            guard value.isValid && (letterOrDigit || shiftedDigit) else { title = "请按 ⌘、⌥ 或 ⌃ 加字母或数字"; return }
            choose(value)
        }
    }
}
