import SwiftUI
import AppKit
import Foundation

struct MainView: View {
    @StateObject private var viewModel: MainViewModel
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var settingsManager: SettingsManager
    
    init(aiService: AIService) {
        let searchService = SearchService()
        self._viewModel = StateObject(
            wrappedValue: MainViewModel(
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
        .frame(width: 680)
        .frame(
            minHeight: 60,
            idealHeight: 60 + calculateContentHeight(),
            maxHeight: 700
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            setupKeyboardHandling()
        }
        .onChange(of: viewModel.modulesItems) { _ in
            // 当模块内容变化时重新计算高度
            updateHeight()
            print("modulesItems: \(viewModel.modulesItems)")
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
        .topBorder()
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
        ).padding(.vertical, 4)
        
        // AI响应内容 - 如果是AI模块且已展开，且有AI回复项被选中
        if section.type == .ai && section.isExpanded {
            aiResponseView
        }
        
        // 文件加载更多按钮 - 如果是文件模块且已展开且有超过10个结果
        if section.type == .file && section.isExpanded && (viewModel.fileResultsCount ?? 0) > 10 {
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
        
        // 遍历所有模块
        for section in viewModel.modules {
            // 标题高度
            totalHeight += 40
            
            if section.type == .calculator {
                totalHeight += 60 // 计算器展开高度
            }
            
            // 模块项高度
            let itemCount = section.items.count
            totalHeight += CGFloat(itemCount) * 42 // 每项高度48
            
            // 特殊模块额外高度
            if section.type == .ai && section.isExpanded {
                // 对AI模块预留更多空间，避免展开时的跳动
                totalHeight += 250 // AI展开高度
            }
            
            // 文件模块加载更多按钮
            if section.type == .file && section.isExpanded && (viewModel.fileResultsCount ?? 0) > 10 {
                totalHeight += 40
            }
            totalHeight = max(100, totalHeight) // 暂时没有定位到为什么只有一项的时候，高度不够的原因，先增加一个最低高度
            print("计算过程：\(section.type),\(totalHeight)")
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
            
            // 处理设置快捷键 Command+逗号 (包括中英文逗号)
            if event.modifierFlags.contains(.command) &&
               (event.charactersIgnoringModifiers == "," || event.charactersIgnoringModifiers == "，") {
                requestOpenSettings()
            }
            
            return handled ? nil : event
        }
    }
    
    // 更新高度
    private func updateHeight() {
        let newHeight = calculateContentHeight()
        let targetHeight = min(60 + newHeight, 700)
        print("计算新高度: \(targetHeight)")
        
        // 优化窗口高度更新机制，使用更平滑的动画
        Task { @MainActor in
            WindowCoordinator.shared.updateWindowHeight(to: targetHeight, animated: true)
        }
    }
    
    // 添加requestFocus方法
    func requestFocus() {
        NotificationCenter.default.post(name: Notification.Name("RequestSearchFocus"), object: nil)
    }
    
    func requestOpenSettings() {
        NotificationCenter.default.post(name: Notification.Name("OpenSettingsNotification"), object: nil)
    }
}

// 窗口协调器（原始代码的一部分）
extension MainViewModel {
    // 为MainViewModel添加的扩展，用于访问缓存的文件结果
    var fileResultsCount: Int? {
        if let fileModule = modules.first(where: { $0.type == .file }) {
            // 如果模块展开，获取文件项（第一个是搜索标题项）
            if fileModule.isExpanded {
                // 获取实际文件结果
                return fileModule.items.dropFirst().count
            }
        }
        return 0
    }
} 

extension View {
    func bottomBorder(height: CGFloat = 0.5, color: Color = Color.gray.opacity(0.3)) -> some View {
        self.overlay(
            Rectangle()
                .frame(height: height)
                .foregroundColor(color),
            alignment: .bottom
        )
    }
    func topBorder(height: CGFloat = 0.5, color: Color = Color.gray.opacity(0.3)) -> some View {
        self.overlay(
            Rectangle()
                .frame(height: height)
                .foregroundColor(color),
            alignment: .top
        )
    }
}
