import SwiftUI
import AppKit

class WindowSizeManager {
    // 使用单例模式集中管理窗口调整
    static let shared = WindowSizeManager()
    
    // 当前窗口高度
    private var currentHeight: CGFloat = 60
    
    private init() {}
    
    // 静态方法为了兼容现有调用
    static func adjustWindowHeight(for height: CGFloat) {
        shared.adjustWindowHeight(for: height)
    }
    
    static func resetWindowHeight() {
        shared.adjustWindowHeight(for: 60)
    }
    
    // 实际执行窗口调整的方法
    func adjustWindowHeight(for height: CGFloat) {
        // 避免重复调整相同高度
        if abs(currentHeight - height) < 1 {
            return
        }
        
        print("调整窗口高度: \(currentHeight) -> \(height)")
        currentHeight = height
        
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                var frame = window.frame
                let oldHeight = frame.size.height
                
                // 保持窗口顶部位置不变，调整高度
                frame.origin.y += (oldHeight - height)
                frame.size.height = height
                
                // 使用动画平滑过渡
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(frame, display: true)
                }
            }
        }
    }
} 