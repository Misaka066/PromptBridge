import Foundation

public struct TranslationShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    // Carbon modifier bits, persisted independently of NSEvent's flag representation.
    public let modifiers: UInt32
    public static let standard = Self(keyCode: 17, modifiers: 1 << 11)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isValid: Bool {
        // Printable positions on ANSI, ISO and JIS keyboards, plus keypad digits.
        // The recorder checks the character against the active keyboard layout.
        let printable = (keyCode <= 47 && keyCode != 36) || [50, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 95].contains(keyCode)
        let required: UInt32 = (1 << 8) | (1 << 11) | (1 << 12)
        return printable && modifiers & required != 0
            && modifiers & ~(required | (1 << 9)) == 0
    }
}
