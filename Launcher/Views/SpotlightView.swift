import SwiftUI
import AppKit

struct SpotlightView: View {
    @StateObject private var viewModel: SpotlightViewModel
    @Environment(\.scenePhase) var scenePhase
    
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
        VStack(spacing: 0) {
            // 搜索栏
            SearchBarView(
                searchText: $viewModel.searchText,
                onClear: {
                    viewModel.resetSearch()
                }
            )
            
            // 内容区域 - 根据状态显示不同内容
            Group {
                if viewModel.showingAIResponse {
                    AIResponseView(
                        aiService: viewModel.aiService, 
                        prompt: viewModel.prompt, 
                        onEscape: {
                            viewModel.exitCurrentMode()
                        },
                        onHeightChange: { newHeight in
                            viewModel.setAIContentHeight(newHeight)
                        }
                    )
                } else if viewModel.showingFileSearch {
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
                } else if !viewModel.searchText.isEmpty && !viewModel.displayResults.isEmpty {
                    // 结果列表
                    ResultListView(
                        results: viewModel.displayResults,
                        selectedIndex: $viewModel.selectedIndex,
                        onItemClick: { result in
                            viewModel.handleItemClick(result)
                        }
                    )
                }
            }
        }
        .frame(width: 680, height: viewModel.height)
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