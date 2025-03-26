import SwiftUI

struct ResultListView: View {
    // 为视图提供静态稳定ID，确保SwiftUI视为同一视图而非重建
    private static let stableViewId = "ResultListView"
    
    let results: [SearchResult]
    @Binding var selectedIndex: Int?
    var onItemClick: (SearchResult) -> Void
    
    // 添加自动选择第一个结果的属性
    var autoSelectFirstResult: Bool = true
    
    // 监控内部状态
    @State private var lastResultCount: Int = 0
    @State private var didSetupInitial: Bool = false
    
    // 添加高度管理引用
    @ObservedObject private var heightManager = HeightManager.shared
    
    var body: some View {
        // 使用稳定的内容，无论结果有无都保持一致的结构
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                // 添加锚点但不占用空间
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
                .id("top") // 移动锚点ID到VStack上
            }
            // 确保ScrollView填满整个空间，没有任何间距
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 明确设置ScrollView四边的内边距为零，消除默认边距
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            // 移除任何可能的内边距
            .padding(0)
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
            .onDisappear {
                lastResultCount = 0
            }
            // 结果数量变化时的处理 - 使用更精确的判断条件
            .onChange(of: results.count, perform: { newCount in
                // 结果数量变化才执行滚动
                if newCount != lastResultCount {
                    lastResultCount = newCount
                    
                    if newCount > 0 {
                        // 设置自动选中第一个
                        if autoSelectFirstResult && selectedIndex == nil {
                            selectedIndex = 0
                        }
                        
                        // 只有在结果数量变化时才需要滚动
                        withAnimation {
                            if let selectedIndex, selectedIndex < newCount {
                                // 滚动到选中的项目
                                proxy.scrollTo("result-\(selectedIndex)", anchor: .center)
                            } else {
                                // 无选中项时滚动到开头
                                proxy.scrollTo("resultListTop", anchor: .top)
                            }
                        }
                    }
                    
                    // 更新高度管理器
                    heightManager.updateContentHeight(
                        calculateContentHeight(),
                        source: "ResultList[\(results.count)]"
                    )
                }
            })
            // 监听选中项变化 - 添加条件判断防止无效滚动
            .onChange(of: selectedIndex, perform: { newIndex in
                if let index = newIndex, index >= 0, index < results.count {
                    // 使用轻微动画滚动到选中项
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            })
        }
        // 添加稳定ID，确保视图不会被重建
        .id(Self.stableViewId)
        // 添加报告尺寸功能
        .reportSize(name: "ResultListView-Outer") { size in
            // 检测到尺寸变化时，更新调试信息
            if !results.isEmpty && heightManager.currentMode == .search {
                print("结果列表尺寸变化: \(size)")
            }
        }
    }
    
    // 计算内容高度的方法
    private func calculateContentHeight() -> CGFloat {
        // 基于结果数量计算高度
        let count = results.count
        return LauncherSize.calculateHeightForItems(count)
    }
} 