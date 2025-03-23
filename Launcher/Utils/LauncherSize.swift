import SwiftUI
import Combine

/// 集中管理启动器大小计算的工具类
struct LauncherSize {
    /// 固定尺寸常量
    struct Fixed {
        /// 搜索栏高度（包含内边距）
        static let searchBarHeight: CGFloat = 60
        
        /// 结果行高度 - 调整为更合适的高度，避免重叠
        static let rowHeight: CGFloat = 48
        
        /// 垂直内边距 - 确保只在顶部添加
        static let verticalPadding: CGFloat = 0
        
        /// 最小内容高度
        static let minContentHeight: CGFloat = 0
        
        /// AI内容最小高度
        static let minAIContentHeight: CGFloat = 200
        
        /// 文件搜索最小高度
        static let minFileSearchHeight: CGFloat = 150
    }
    
    /// 每种视图模式的高度限制
    struct HeightLimits {
        static let searchMin: CGFloat = Fixed.searchBarHeight
        static let searchMax: CGFloat = 500
        
        static let fileSearchMin: CGFloat = Fixed.searchBarHeight + 100
        static let fileSearchMax: CGFloat = 500
        
        static let aiResponseMin: CGFloat = Fixed.searchBarHeight + 200
        static let aiResponseMax: CGFloat = 600
    }
    
    /// 为特定视图模式计算适当的高度
    /// - Parameters:
    ///   - mode: 视图模式
    ///   - itemCount: 项目数量（用于计算结果列表高度）
    /// - Returns: 总窗口高度
    static func getHeightForMode(_ mode: ViewMode, itemCount: Int = 0) -> CGFloat {
        switch mode {
        case .search:
            // 基础高度 + 内容高度
            let contentHeight = getContentHeightForItems(itemCount)
            return Fixed.searchBarHeight + contentHeight
            
        case .fileSearch:
            // 文件搜索模式 - 使用最小高度或基于项目数量的高度
            let contentHeight = max(
                Fixed.minFileSearchHeight,
                getContentHeightForItems(itemCount)
            )
            return Fixed.searchBarHeight + contentHeight
            
        case .aiResponse:
            // AI响应模式 - 使用预设的最小高度
            return Fixed.searchBarHeight + Fixed.minAIContentHeight
        }
    }
    
    /// 根据项目数量计算内容高度
    /// - Parameter count: 项目数量
    /// - Returns: 内容区域高度
    private static func getContentHeightForItems(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        
        // 计算所有项目高度，不添加额外内边距
        let rawHeight = CGFloat(count) * Fixed.rowHeight
        
        // 限制最大高度，避免窗口过大
        return min(rawHeight, 400)
    }
    
    /// 为自定义内容高度计算窗口高度
    /// - Parameters:
    ///   - contentHeight: 内容高度
    ///   - mode: 视图模式（用于应用不同的限制）
    /// - Returns: 总窗口高度
    static func getHeightForCustomContent(_ contentHeight: CGFloat, mode: ViewMode) -> CGFloat {
        let minContentHeight: CGFloat
        let maxContentHeight: CGFloat
        
        // 根据不同模式设置最小/最大内容高度
        switch mode {
        case .search:
            minContentHeight = Fixed.minContentHeight
            maxContentHeight = 400
        case .fileSearch:
            minContentHeight = Fixed.minFileSearchHeight
            maxContentHeight = 400
        case .aiResponse:
            minContentHeight = Fixed.minAIContentHeight
            maxContentHeight = 500
        }
        
        // 限制内容高度在合理范围内
        let clampedHeight = max(minContentHeight, min(contentHeight, maxContentHeight))
        
        // 返回搜索栏高度 + 内容高度
        return Fixed.searchBarHeight + clampedHeight
    }
    
    /// 计算基于项目数量的内容高度
    static func calculateHeightForItems(_ itemCount: Int) -> CGFloat {
        if itemCount == 0 {
            return 0
        }
        // 修改：移除垂直内边距，只计算行高
        return CGFloat(itemCount) * Fixed.rowHeight
    }
    
    /// 计算最终窗口高度，考虑屏幕限制
    static func calculateWindowHeight(baseHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        let totalHeight = baseHeight + contentHeight
        
        // 考虑屏幕限制
        let maxScreenHeight = (NSScreen.main?.frame.height ?? 1000) * 0.7
        return min(totalHeight, maxScreenHeight)
    }
}

/// 全局高度管理器 - 集中管理所有视图高度计算和更新
@MainActor
class HeightManager: ObservableObject {
    static let shared = HeightManager()
    
    // 高度相关状态
    @Published var currentHeight: CGFloat = LauncherSize.Fixed.searchBarHeight
    @Published var contentHeight: CGFloat = 0
    @Published var currentMode: ViewMode = .search
    
    // 调试状态
    @Published var lastUpdateSource: String = ""
    @Published var debugMode: Bool = false
    
    // 防止频繁更新的节流机制
    private var heightUpdateTask: Task<Void, Never>? = nil
    private var isUpdating: Bool = false
    
    private init() {
        // 初始化时不需要特殊逻辑
    }
    
    /// 更新内容高度的统一入口
    func updateContentHeight(_ newHeight: CGFloat, source: String) {
        // 记录更新来源，用于调试
        self.lastUpdateSource = source
        
        // 检查是否是有意义的变化
        guard abs(self.contentHeight - newHeight) > 1.0 else {
            print("【高度管理】忽略微小高度变化: \(self.contentHeight) -> \(newHeight)")
            return
        }
        
        // 取消之前的任务
        heightUpdateTask?.cancel()
        
        // 创建新的更新任务
        heightUpdateTask = Task {
            // 如果已经在更新中，等待一段时间
            if isUpdating {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50毫秒
            }
            
            // 标记更新开始
            isUpdating = true
            
            // 限制高度在合理范围内
            let newTotalHeight = calculateHeightForMode(self.currentMode, contentHeight: newHeight)
            
            // 更新状态
            self.contentHeight = newHeight
            self.currentHeight = newTotalHeight
            
            // 应用窗口高度变化
            WindowCoordinator.shared.updateWindowHeight(to: newTotalHeight, animated: true)
            
            // 延迟一段时间后重置更新状态
            try? await Task.sleep(nanoseconds: 200_000_000) // 200毫秒
            isUpdating = false
            
            print("【高度管理】高度更新完成: \(newTotalHeight), 来源: \(source)")
        }
    }
    
    /// 切换视图模式
    func switchToMode(_ mode: ViewMode, initialContentHeight: CGFloat? = nil) {
        // 保存当前模式
        let oldMode = self.currentMode
        self.currentMode = mode
        
        // 根据模式计算初始高度
        let newContentHeight: CGFloat
        if let height = initialContentHeight {
            newContentHeight = height
        } else {
            switch mode {
            case .search:
                newContentHeight = 0
            case .fileSearch:
                newContentHeight = LauncherSize.Fixed.minFileSearchHeight
            case .aiResponse:
                newContentHeight = LauncherSize.Fixed.minAIContentHeight
            }
        }
        
        // 更新高度
        self.contentHeight = newContentHeight
        self.currentHeight = calculateHeightForMode(mode, contentHeight: newContentHeight)
        
        // 应用到窗口 - 根据模式变化决定是否使用动画
        let shouldAnimate = !(oldMode == .search && mode != .search && newContentHeight > 200)
        WindowCoordinator.shared.updateWindowHeight(to: self.currentHeight, animated: shouldAnimate)
        
        print("【高度管理】模式切换: \(oldMode) -> \(mode), 新高度: \(self.currentHeight)")
    }
    
    /// 重置到初始状态
    func resetToInitialState() {
        // 重置所有状态
        self.currentMode = .search
        self.contentHeight = 0
        self.currentHeight = LauncherSize.Fixed.searchBarHeight
        
        // 应用到窗口
        WindowCoordinator.shared.resetWindowHeight()
        
        print("【高度管理】重置到初始状态")
    }
    
    /// 计算特定模式下的总高度
    private func calculateHeightForMode(_ mode: ViewMode, contentHeight: CGFloat) -> CGFloat {
        let minHeight: CGFloat
        let maxHeight: CGFloat
        
        // 根据模式设置限制
        switch mode {
        case .search:
            minHeight = LauncherSize.HeightLimits.searchMin
            maxHeight = LauncherSize.HeightLimits.searchMax
        case .fileSearch:
            minHeight = LauncherSize.HeightLimits.fileSearchMin
            maxHeight = LauncherSize.HeightLimits.fileSearchMax
        case .aiResponse:
            minHeight = LauncherSize.HeightLimits.aiResponseMin
            maxHeight = LauncherSize.HeightLimits.aiResponseMax
        }
        
        // 计算并限制在合理范围内
        let calculatedHeight = LauncherSize.Fixed.searchBarHeight + contentHeight
        let constrainedHeight = max(minHeight, min(calculatedHeight, maxHeight))
        
        return constrainedHeight
    }
    
    /// 计算基于搜索结果项目数量的高度
    func calculateHeightForResults(_ results: [SearchResult]) -> CGFloat {
        if results.isEmpty {
            return LauncherSize.Fixed.searchBarHeight
        }
        
        // 计算内容高度并更新
        let itemCount = results.count
        let newContentHeight = LauncherSize.calculateHeightForItems(itemCount)
        self.contentHeight = newContentHeight
        
        // 计算总高度
        let totalHeight = calculateHeightForMode(.search, contentHeight: newContentHeight)
        self.currentHeight = totalHeight
        
        return totalHeight
    }
    
    /// 获取调试信息
    var debugInfo: String {
        return """
        模式: \(currentMode)
        内容高度: \(Int(contentHeight))
        总高度: \(Int(currentHeight))
        最后更新来源: \(lastUpdateSource)
        """
    }
} 