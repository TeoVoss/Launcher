import SwiftUI
import AppKit

// 窗口协调器高度变更通知名称
let WindowCoordinatorDidUpdateHeight = Notification.Name("WindowCoordinatorDidUpdateHeight")

/// 窗口尺寸和变化的集中协调器
/// 负责高效处理窗口大小变化，避免频繁更新和UI闪烁
class WindowCoordinator: NSObject {
    /// 单例实例
    static let shared = WindowCoordinator()
    
    private var currentUpdateTask: Task<Void, Never>? = nil
    
    /// 当前窗口高度
    private(set) var currentHeight: CGFloat = 60
    
    /// 标记是否正在执行动画
    private var isAnimating: Bool = false
    
    /// 窗口调整队列 - 使用单一队列避免多次计算和调整
    private var animationQueue = DispatchQueue(label: "com.launcher.windowAnimation")
    
    /// 基本动画持续时间
    private let animationDuration: TimeInterval = 0.25
    
    /// 窗口是否可见
    private var isWindowVisible: Bool {
        return self.window.isVisible
    }
    
    /// 获取当前主窗口
    private var window: NSWindow = NSWindow()
    
    private override init() {
        super.init()
    }
    
    func setWindow(_ window: NSWindow) {
        self.window = window
    }
    
    /// 显示主窗口
    func showWindow() {
        guard let window = NSApp.windows.first(where: { $0.title == "Launcher" }) else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// 更新窗口高度的统一方法
    /// - Parameters:
    ///   - height: 目标高度
    ///   - animated: 是否使用动画过渡
    func updateWindowHeight(to height: CGFloat, animated: Bool = true) {
        // 避免不必要的高度更新或者过小的变化
        let minHeightDelta: CGFloat = 2.0
        guard abs(currentHeight - height) > minHeightDelta else {
//            print("【窗口高度】跳过高度更新 - 当前:\(currentHeight), 目标:\(height)")
            return
        }
        
        // 防止高度更新过于频繁，使用延迟批处理
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyDelayedHeightChange), object: nil)
        
        // 记录目标高度，但延迟应用
//        print("【窗口高度】开始更新窗口高度: \(height), 动画: \(animated), 当前高度: \(currentHeight)")
        let oldHeight = currentHeight
        currentHeight = height
        
        
        // 使用更高效的命令分组来避免频繁更新
        if abs(oldHeight - height) > 100 {
            // 对于大幅度高度变化，使用更长的延迟，让UI有时间准备
            let animatedValue = NSNumber(value: animated)
            self.perform(#selector(applyDelayedHeightChange), with: animatedValue, afterDelay: 0.03)
        } else {
            // 小幅度变化使用标准延迟
            let animatedValue = NSNumber(value: animated)
            self.perform(#selector(applyDelayedHeightChange), with: animatedValue, afterDelay: 0.01)
        }
    }
    
    /// 延迟应用高度变化的实际方法
    @objc private func applyDelayedHeightChange(_ animatedObj: NSNumber?) {
        let animated = animatedObj?.boolValue ?? true
        
        if animated {
            // 使用系统动画函数进行平滑过渡
//            print("【窗口高度】开始动画更新窗口高度")
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2  // 稍微延长动画时间
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0, 1, 0.05, 1)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frameForHeight(currentHeight), display: true)
            } completionHandler: {
//                print("【窗口高度】动画完成，新高度: \(self.currentHeight)")
                // 延迟发送通知，确保UI已经稳定
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.12))
                    if Task.isCancelled { return }
                    NotificationCenter.default.post(name: WindowCoordinatorDidUpdateHeight, object: nil)
                }
            }
        } else {
            // 立即应用高度变化
//            print("【窗口高度】立即更新窗口高度: \(currentHeight)")
            window.setFrame(frameForHeight(currentHeight), display: true)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.03))
                if Task.isCancelled { return }
                NotificationCenter.default.post(name: WindowCoordinatorDidUpdateHeight, object: nil)
            }
        }
    }
    
    /// 计算指定高度的窗口框架
    private func frameForHeight(_ height: CGFloat) -> NSRect {
//        guard let window = self.window else {
//            return NSRect(x: 0, y: 0, width: 680, height: height)
//        }
        
        var frame = window.frame
        let oldHeight = frame.size.height
        
        // 保持窗口顶部位置不变，只调整高度
        frame.origin.y += (oldHeight - height)
        frame.size.height = height
        
        return frame
    }
    
    /// 用于批量处理的高度变更应用方法
    @objc private func applyWindowHeightChange() {
        // 这个方法只是一个占位符，实际上高度变更在updateWindowHeight中直接处理
//        print("应用窗口高度变更")
    }
    
    /// 重置窗口到初始高度
    func resetWindowHeight() {
        updateWindowHeight(to: 60, animated: true)
    }
} 

extension Animation {
    static var customEaseOut: Animation {
        Animation.timingCurve(0.0, 0.0, 0.2, 1.0, duration: 0.3)
    }
    
    // 自定义动画：前80%瞬间完成，后20%为easeOut
    static var quickThenEaseOut: Animation {
        Animation.timingCurve(0.8, 0.0, 0.9, 0.5, duration: 0.3)
    }
}
