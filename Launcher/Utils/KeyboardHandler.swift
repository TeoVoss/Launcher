import SwiftUI
import AppKit

/// 键盘事件处理工具类
class KeyboardHandler {
    /// 处理键盘按下事件
    /// - Parameters:
    ///   - event: 键盘事件
    ///   - onEscape: Escape 键回调
    ///   - onEnter: Enter 键回调
    ///   - onArrowUp: 向上箭头回调
    ///   - onArrowDown: 向下箭头回调
    /// - Returns: 是否已处理事件
    static func handleKeyDown(
        event: NSEvent,
        onEscape: @escaping () -> Void,
        onEnter: @escaping () -> Void,
        onArrowUp: @escaping () -> Void,
        onArrowDown: @escaping () -> Void
    ) -> Bool {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        
        // 检查是否按下了控制键 (Command, Option等)
        let hasModifiers = modifierFlags.contains(.command) ||
                          modifierFlags.contains(.option) ||
                          modifierFlags.contains(.control)
        
        if !hasModifiers {
            // 根据键码处理不同的键
            switch keyCode {
            case 53: // Escape 键
                onEscape()
                return true
                
            case 36, 76: // Enter 或 Return 键
                onEnter()
                return true
                
            case 126: // 向上箭头
                onArrowUp()
                return true
                
            case 125: // 向下箭头
                onArrowDown()
                return true
                
            default:
                break
            }
        }
        
        // 未处理的事件返回 false
        return false
    }
} 