import SwiftUI

struct ResultListView: View {
    // 为视图提供静态稳定ID，确保SwiftUI视为同一视图而非重建
    private static let stableViewId = "ResultListView"
    
    let results: [SearchResult]
    @Binding var selectedIndex: Int?
    var onItemClick: (SearchResult) -> Void
    
    // 监控内部状态
    @State private var lastResultCount: Int = 0
    @State private var didSetupInitial: Bool = false
    
    var body: some View {
        // 创建稳定的内容，无论结果有无都保持一致的结构
        ScrollViewReader { proxy in
            ScrollView {
                // 添加锚点用于滚动到顶部
                Color.clear.frame(height: 0).id("top")
                
                // 使用VStack而不是LazyVStack，确保布局一次性计算完成
                VStack(spacing: 0) {
                    // 条件内容 - 只在有结果时渲染项目
                    if !results.isEmpty {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            // 使用单独的容器包装每一项，确保边界清晰
                            VStack(spacing: 0) {
                                ResultRowView(
                                    result: result,
                                    isSelected: selectedIndex == index
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = index
                                    onItemClick(result)
                                }
                            }
                            .frame(height: LauncherSize.Fixed.rowHeight)
                            .id(index)
                        }
                    } else {
                        // 即使没有结果也保持VStack存在，只是不显示内容
                        Color.clear
                            .frame(height: 0)
                    }
                }
                // 添加上方内边距，但不添加底部内边距，避免不必要的空间
                .padding(.top, LauncherSize.Fixed.verticalPadding)
            }
            // 移除滚动指示器，优化视觉效果
            .scrollIndicators(.hidden)
            // 简单的初始化逻辑 - 使用onAppear和onChange分开处理
            .onAppear {
                if !didSetupInitial {
                    didSetupInitial = true
                    // 记录初始结果数
                    lastResultCount = results.count
                    
                    // 确保ScrollView从顶部开始
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(nil) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                        
                        // 默认选中第一项 - 只在有结果时设置
                        if selectedIndex == nil && !results.isEmpty {
                            selectedIndex = 0
                        }
                    }
                }
            }
            // 结果数量变化时的处理 - 使用更精确的判断条件
            .onChange(of: results.count) { newCount in
                // 结果数量变化才执行滚动
                if newCount != lastResultCount {
                    // 更新结果数量缓存
                    lastResultCount = newCount
                    
                    // 滚动到顶部 - 延迟执行确保布局完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(nil) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                        
                        // 重新设置选中项
                        if newCount > 0 && (selectedIndex == nil || selectedIndex! >= newCount) {
                            selectedIndex = 0
                        } else if newCount == 0 {
                            selectedIndex = nil
                        }
                    }
                }
            }
            // 监听选中项变化 - 添加条件判断防止无效滚动
            .onChange(of: selectedIndex) { newIndex in
                if let index = newIndex, index >= 0, index < results.count {
                    // 使用轻微动画滚动到选中项
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        // 添加稳定ID，确保视图不会被重建
        .id(Self.stableViewId)
    }
} 