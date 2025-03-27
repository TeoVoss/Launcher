import SwiftUI
import AppKit
import Foundation

struct ModularSpotlightView: View {
    @StateObject private var viewModel: ModuleViewModel
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var settingsManager: SettingsManager
    
    init(aiService: AIService) {
        let searchService = SearchService()
        self._viewModel = StateObject(
            wrappedValue: ModuleViewModel(
                searchService: searchService,
                aiService: aiService
            )
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            SearchBarView(
                searchText: $viewModel.searchText
            )
            .frame(height: 60)
            
            // 模块化内容区域
            contentView
        }
        .frame(width: 680, height: min(700, 60 + calculateContentHeight()))
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            setupKeyboardHandling()
        }
        .onChange(of: viewModel.aiModuleExpanded) { _ in
            updateHeight()
        }
        .onChange(of: viewModel.fileModuleExpanded) { _ in
            updateHeight()
        }
        .onChange(of: scenePhase) { value in
            if value == .active {
                viewModel.requestFocus()
            }
        }
    }
    
    // 内容区域视图
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(viewModel.modules.enumerated()), id: \.element.type.rawValue) { _, section in
                    moduleSectionView(for: section)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(0)
    }
    
    // 单个模块区域视图
    @ViewBuilder
    private func moduleSectionView(for section: ModuleSection) -> some View {
        ModuleSectionView(
            section: section,
            selectedIndex: viewModel.selectedItemIndex,
            onSelectItem: { index in
                viewModel.handleItemSelection(index)
            },
            onExpandHeader: { moduleType in
//                viewModel.toggleModule(moduleType)
            }
        )
        
        // AI响应内容 - 如果是AI模块且已展开，且有AI回复项被选中
        if section.type == .ai && section.isExpanded {
            aiResponseView
        }
        
        // 文件加载更多按钮 - 如果是文件模块且已展开且有超过10个结果
        if section.type == .file && section.isExpanded && (viewModel.cachedFileResults?.count ?? 0) > 10 {
            loadMoreView
        }
    }
    
    // AI响应视图
    private var aiResponseView: some View {
        AIResponseView(
            aiService: viewModel.aiService,
            prompt: viewModel.aiPrompt,
            onEscape: {
                // 点击Escape时切换回非选中状态
                if viewModel.selectedItemIndex?.moduleType == .ai && 
                   viewModel.selectedItemIndex?.itemIndex == 1 {
                    viewModel.selectedItemIndex = SelectableItemIndex(
                        moduleType: .ai,
                        itemIndex: 0,
                        isHeader: true
                    )
                } else {
                    viewModel.toggleAIModule()
                }
            },
            onHeightChange: { _ in }
        )
        .padding(.top, 4)
        .transition(.opacity)
        .id(viewModel.aiPrompt) // 确保提示变化时视图会重新加载
    }
    
    // 加载更多按钮视图
    private var loadMoreView: some View {
        LoadMoreView {
            viewModel.loadMoreFileResults()
        }
    }
    
    // 计算内容总高度
    private func calculateContentHeight() -> CGFloat {
        var totalHeight: CGFloat = 0
        
        // 预先为AI模块预留足够的空间，避免展开时的高度突变
        let aiModuleExists = viewModel.modules.contains { $0.type == .ai }
        let aiExpanded = viewModel.aiModuleExpanded
        
        // 遍历所有模块
        for section in viewModel.modules {
            // 标题高度
            totalHeight += 30
            
            // 模块项高度
            let itemCount = section.items.count
            totalHeight += CGFloat(itemCount) * 48 // 每项高度48
            
            // 特殊模块额外高度
            if section.type == .ai && section.isExpanded {
                // 对AI模块预留更多空间，避免展开时的跳动
                totalHeight += 250 // AI展开高度
            }
            
            // 文件模块加载更多按钮
            if section.type == .file && section.isExpanded && (viewModel.cachedFileResults?.count ?? 0) > 10 {
                totalHeight += 40
            }
        }
        
        // 最小内容高度保障
        if aiModuleExists && aiExpanded {
            totalHeight = max(totalHeight, 350) // 确保AI展开时有足够空间
        }
        
        return totalHeight
    }
    
    // 设置键盘处理
    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = KeyboardHandler.handleKeyDown(
                event: event,
                onEscape: {
                    viewModel.handleKeyboardNavigation(.escape)
                },
                onEnter: {
                    viewModel.handleKeyboardNavigation(.enter)
                },
                onArrowUp: {
                    viewModel.handleKeyboardNavigation(.up)
                },
                onArrowDown: {
                    viewModel.handleKeyboardNavigation(.down)
                }
            )
            
            return handled ? nil : event
        }
    }
    
    // 更新高度
    private func updateHeight() {
        let newHeight = calculateContentHeight()
        print("计算新高度: \(newHeight)")
        // 优化窗口高度更新机制，使用更平滑的动画
        DispatchQueue.main.async {
            WindowCoordinator.shared.updateWindowHeight(to: 60 + newHeight, animated: true)
        }
    }
    
    // 添加requestFocus方法
    func requestFocus() {
        NotificationCenter.default.post(name: Notification.Name("RequestSearchFocus"), object: nil)
    }
}

// 窗口协调器（原始代码的一部分）
extension ModuleViewModel {
    func requestFocus() {
        // 通过NotificationCenter发送请求焦点通知
        
    }
    
    // 为ModuleViewModel添加的扩展，用于访问缓存的文件结果
    var cachedFileResults: [SearchResult]? {
        if let fileModule = modules.first(where: { $0.type == .file }) {
            // 如果模块展开，获取文件项（第一个是搜索标题项）
            if fileModule.isExpanded {
                // 获取实际文件结果
                let fileItems = fileModule.items.dropFirst()
                if !fileItems.isEmpty {
                    return fileItems.compactMap { item in
                        if let fileItem = item as? FileItem {
                            return fileItem.searchResult
                        }
                        return nil
                    }
                }
            }
        }
        return nil
    }
} 
