import SwiftUI

/// 集中管理启动器大小计算的工具类
struct LauncherSize {
    /// 固定尺寸常量
    struct Fixed {
        /// 搜索栏高度（包含内边距）
        static let searchBarHeight: CGFloat = 60
        
        /// 结果行高度 - 调整为更合适的高度，避免重叠
        static let rowHeight: CGFloat = 48
        
        /// 垂直内边距 - 确保只在顶部添加
        static let verticalPadding: CGFloat = 8
        
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
        
        // 计算所有项目高度 + 仅顶部的垂直内边距
        let rawHeight = CGFloat(count) * Fixed.rowHeight + Fixed.verticalPadding
        
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
        return CGFloat(itemCount) * Fixed.rowHeight + Fixed.verticalPadding * 2
    }
    
    /// 计算最终窗口高度，考虑屏幕限制
    static func calculateWindowHeight(baseHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        let totalHeight = baseHeight + contentHeight
        
        // 考虑屏幕限制
        let maxScreenHeight = (NSScreen.main?.frame.height ?? 1000) * 0.7
        return min(totalHeight, maxScreenHeight)
    }
} 