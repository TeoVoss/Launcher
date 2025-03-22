import SwiftUI
import AppKit

class KeyboardHandler {
    static func handleKeyDown(
        event: NSEvent,
        onEscape: @escaping () -> Void,
        onEnter: @escaping () -> Void,
        onArrowUp: @escaping () -> Void,
        onArrowDown: @escaping () -> Void
    ) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            onEscape()
            return true
        case 36: // Return / Enter
            onEnter()
            return true
        case 125: // Down Arrow
            onArrowDown()
            return true
        case 126: // Up Arrow
            onArrowUp()
            return true
        default:
            return false
        }
    }
} 