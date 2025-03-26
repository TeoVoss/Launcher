import SwiftUI
import AppKit

// 窗口协调器高度变更通知名称
let WindowCoordinatorDidUpdateHeight = Notification.Name("WindowCoordinatorDidUpdateHeight")

/// 窗口尺寸和变化的集中协调器
/// 负责高效处理窗口大小变化，避免频繁更新和UI闪烁
class WindowCoordinator: NSObject {
    /// 单例实例
    static let shared = WindowCoordinator()
    
    /// 当前窗口高度
    private(set) var currentHeight: CGFloat = 60
    
    /// 标记是否正在执行动画
    private var isAnimating: Bool = false
    
    /// 窗口调整队列 - 使用单一队列避免多次计算和调整
    private var animationQueue = DispatchQueue(label: "com.launcher.windowAnimation")
    
    /// 基本动画持续时间
    private let animationDuration: TimeInterval = 0.25
    
    /// 当前视图模式
    private(set) var currentViewMode: ViewMode = .search
    
    /// 上一个活跃的视图模式，用于从特殊模式返回
    private(set) var lastActiveViewMode: ViewMode = .search
    
    /// 窗口是否可见
    private var isWindowVisible: Bool {
        return NSApp.windows.first(where: { $0.title == "Launcher" })?.isVisible ?? false
    }
    
    /// 获取当前主窗口
    private var window: NSWindow? {
        return NSApp.windows.first(where: { $0.title == "Launcher" })
    }
    
    private override init() {
        super.init()
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
        
        // 更新高度前确保窗口可见
        if !isWindowVisible {
//            print("【窗口高度】窗口不可见，正在显示窗口")
            showWindow()
        }
        
        // 使用更高效的命令分组来避免频繁更新
        if abs(oldHeight - height) > 100 {
            // 对于大幅度高度变化，使用更长的延迟，让UI有时间准备
            let animatedValue = NSNumber(value: animated)
            self.perform(#selector(applyDelayedHeightChange), with: animatedValue, afterDelay: 0.08)
        } else {
            // 小幅度变化使用标准延迟
            let animatedValue = NSNumber(value: animated)
            self.perform(#selector(applyDelayedHeightChange), with: animatedValue, afterDelay: 0.05)
        }
    }
    
    /// 延迟应用高度变化的实际方法
    @objc private func applyDelayedHeightChange(_ animatedObj: NSNumber?) {
        let animated = animatedObj?.boolValue ?? true
        
        if animated {
            // 使用系统动画函数进行平滑过渡
//            print("【窗口高度】开始动画更新窗口高度")
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3  // 稍微延长动画时间
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window?.animator().setFrame(frameForHeight(currentHeight), display: false)
            } completionHandler: {
//                print("【窗口高度】动画完成，新高度: \(self.currentHeight)")
                // 延迟发送通知，确保UI已经稳定
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    NotificationCenter.default.post(name: WindowCoordinatorDidUpdateHeight, object: nil)
                }
            }
        } else {
            // 立即应用高度变化
//            print("【窗口高度】立即更新窗口高度: \(currentHeight)")
            window?.setFrame(frameForHeight(currentHeight), display: true)
            
            // 即使没有动画也延迟发送通知
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                NotificationCenter.default.post(name: WindowCoordinatorDidUpdateHeight, object: nil)
            }
        }
    }
    
    /// 计算指定高度的窗口框架
    private func frameForHeight(_ height: CGFloat) -> NSRect {
        guard let window = self.window else {
            return NSRect(x: 0, y: 0, width: 680, height: height)
        }
        
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
    
    /// 处理视图模式转换
    func handleModeTransition(to viewMode: ViewMode, customHeight: CGFloat? = nil, withAnimation: Bool = true) {
        print("处理视图转换：\(viewMode), 自定义高度：\(String(describing: customHeight))")
        
        // 避免相同模式下的重复转换
        guard currentViewMode != viewMode else {
            // 即使在相同模式下，如果高度变了，也要更新窗口高度
            if let height = customHeight {
                updateWindowHeight(to: height, animated: withAnimation)
            }
            return
        }
        
        // 计算新模式的初始高度
        let initialHeight: CGFloat
        
        if let customHeight = customHeight {
            // 使用自定义高度
            initialHeight = customHeight
        } else {
            // 使用模式默认高度
            initialHeight = LauncherSize.getHeightForMode(viewMode)
        }
        
        // 准备过渡前后的视觉状态
        let from = currentViewMode
        let to = viewMode
        
        // 记录模式变更前的状态
        lastActiveViewMode = currentViewMode
        
        // 更新当前模式
        currentViewMode = viewMode
        
        // 视图转换优化：根据转换类型选择不同的过渡动画
        if from == .aiResponse && to == .search {
            // 从AI对话返回到主界面时的特殊处理
            // 先设置模式，延迟调整高度，避免闪烁
            DispatchQueue.main.async {
                self.updateWindowHeight(to: initialHeight, animated: withAnimation)
            }
        } else if from == .search && to == .aiResponse {
            // 从主界面到AI对话时，先调整高度再切换视图
            self.updateWindowHeight(to: initialHeight, animated: withAnimation)
        } else {
            // 其他模式转换使用标准过渡
            self.updateWindowHeight(to: initialHeight, animated: withAnimation)
        }
    }
} 
