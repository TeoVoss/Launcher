import SwiftUI
import AppKit

// 删除无搜索结果视图，使用简单的空白状态
// 删除NoResultsView结构体

struct SpotlightView: View {
    @StateObject private var viewModel: SpotlightViewModel
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject private var heightManager = HeightManager.shared
    
    init(aiService: AIService) {
        let searchService = SearchService()
        self._viewModel = StateObject(
            wrappedValue: SpotlightViewModel(
                searchService: searchService,
                aiService: aiService
            )
        )
    }
    
    var body: some View {
        // 关键点：固定外层ID标识
        VStack(spacing: 0) {
            // 搜索栏
            SearchBarView(
                searchText: $viewModel.searchText,
                onClear: {
                    viewModel.resetSearch()
                }
            )
            .frame(height: 60)  // 明确总高度为60像素（包含内边距）
            .reportSize(name: "SearchBarView")
            
            // 内容区域 - 创建稳定容器，防止重新创建
            ZStack {
                // 1. 外层容器始终存在，不会被移除
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 2. 显示AI响应
                if viewModel.showingAIResponse {
                    AIResponseView(
                        aiService: viewModel.aiService, 
                        prompt: viewModel.prompt, 
                        onEscape: {
                            viewModel.exitCurrentMode()
                        },
                        onHeightChange: { newHeight in
                            // 修改：使用HeightManager更新高度
                            heightManager.updateContentHeight(newHeight, source: "AIResponseView")
                        }
                    )
                    .transition(.opacity)
                    // 关键点：使用固定ID
                    .id("AIResponseView")
                    .reportSize(name: "AIResponseView")
                }
                
                // 3. 显示文件搜索
                if viewModel.showingFileSearch {
                    FileSearchView(
                        searchService: viewModel.searchService,
                        searchText: $viewModel.searchText,
                        selectedIndex: $viewModel.selectedIndex,
                        onResultSelected: { result in
                            viewModel.searchService.executeResult(result)
                        },
                        onResultsChanged: {
                            // 不再主动调整高度，依靠观察者模式
                        }
                    )
                    .transition(.opacity)
                    // 关键点：使用固定ID
                    .id("FileSearchView")
                    .reportSize(name: "FileSearchView")
                }
                
                // 4. 显示搜索结果 - 关键点：始终存在，仅通过条件隐藏，而不是移除重建
                ResultListView(
                    results: viewModel.displayResults,
                    selectedIndex: $viewModel.selectedIndex,
                    onItemClick: { result in
                        viewModel.handleItemClick(result)
                    }
                )
                // 关键点：通过opacity控制显示隐藏，而不是条件渲染
                .opacity((!viewModel.searchText.isEmpty && !viewModel.displayResults.isEmpty && 
                         !viewModel.showingAIResponse && !viewModel.showingFileSearch) ? 1 : 0)
                .allowsHitTesting((!viewModel.searchText.isEmpty && !viewModel.displayResults.isEmpty && 
                                  !viewModel.showingAIResponse && !viewModel.showingFileSearch))
                .reportSize(name: "ResultListView")
                .contentHeightReader { height in
                    // 只在显示时才更新高度
                    if height > 0 && !viewModel.showingAIResponse && !viewModel.showingFileSearch && 
                       !viewModel.displayResults.isEmpty {
                        // 修改：使用HeightManager更新高度
                        heightManager.updateContentHeight(height, source: "ResultListView")
                    }
                }
            }
            .padding(.top, 0) // 确保内容区域顶部无间距
            .padding(.all, 0) // 确保四边都没有间距
        }
        // 固定整个视图树的ID
        .id("MainSpotlightView")
        // 修改：使用HeightManager的高度
        .frame(width: 680, height: heightManager.currentHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            setupKeyboardHandling()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.requestFocus()
            }
        }
        // 添加调试信息面板
        .debugInfo(heightManager.debugInfo)
        .reportSize(name: "SpotlightView")
    }
    
    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = KeyboardHandler.handleKeyDown(
                event: event,
                onEscape: {
                    if viewModel.showingAIResponse || viewModel.showingFileSearch {
                        viewModel.exitCurrentMode()
                    } else if !viewModel.searchText.isEmpty {
                        viewModel.resetSearch()
                    } else {
                        // 完全退出
                        NSApp.hide(nil)
                    }
                },
                onEnter: {
                    viewModel.handleSubmit()
                },
                onArrowUp: {
                    if viewModel.displayResults.isEmpty { return }
                    
                    if let currentIndex = viewModel.selectedIndex {
                        viewModel.selectedIndex = max(currentIndex - 1, 0)
                    } else {
                        viewModel.selectedIndex = 0
                    }
                },
                onArrowDown: {
                    if viewModel.displayResults.isEmpty { return }
                    
                    if let currentIndex = viewModel.selectedIndex {
                        viewModel.selectedIndex = min(currentIndex + 1, viewModel.displayResults.count - 1)
                    } else {
                        viewModel.selectedIndex = 0
                    }
                }
            )
            
            return handled ? nil : event
        }
    }
    
    func requestFocus() {
        viewModel.requestFocus()
    }
    
    func resetSearch() {
        viewModel.resetSearch()
    }
}

// 更高效的内容高度读取修饰器
struct ContentHeightReaderModifier: ViewModifier {
    let onChange: (CGFloat) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: HeightPreferenceKey.self, value: geo.size.height)
                        .onPreferenceChange(HeightPreferenceKey.self) { height in
                            onChange(height)
                        }
                }
            )
    }
}

// 定义高度偏好键
struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// 为View提供便捷扩展
extension View {
    func contentHeightReader(onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(ContentHeightReaderModifier(onChange: onChange))
    }
} 