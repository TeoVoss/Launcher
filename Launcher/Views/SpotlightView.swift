import SwiftUI
import AppKit
import Foundation

// 删除无搜索结果视图，使用简单的空白状态
// 删除NoResultsView结构体

struct SpotlightView: View {
    @StateObject private var viewModel: SpotlightViewModel
    @Environment(\.scenePhase) var scenePhase
    private let debouncer = Debouncer(delay: 0.3)
    
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
            .frame(height: 60)
            
            // 统一的滚动视图容器
            ScrollView {
                VStack(spacing: 8) {
                    // 1. AI对话视图区域 - 可折叠/展开
                    if viewModel.shouldShowAIOption && !viewModel.searchText.isEmpty {
                        VStack(spacing: 0) {
                            // AI对话折叠标题栏
                            Button(action: {
                                viewModel.toggleAIResponse()
                            }) {
                                HStack {
                                    Image(systemName: "brain.fill")
                                        .foregroundColor(.secondary)
                                    Text("AI 助手")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: viewModel.aiResponseExpanded ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                            .cornerRadius(8)
                            
                            // AI响应内容 - 当展开时显示
                            if viewModel.aiResponseExpanded {
                                AIResponseView(
                                    aiService: viewModel.aiService, 
                                    prompt: viewModel.prompt, 
                                    onEscape: {
                                        viewModel.toggleAIResponse()
                                    },
                                    onHeightChange: { _ in }
                                )
                                .padding(.horizontal, 4)
                                .padding(.top, 4)
                                .transition(.opacity)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    
                    // 2. 应用程序搜索结果 - 始终显示，没有结果时为空
                    if !viewModel.displayResults.isEmpty {
                        VStack(spacing: 0) {
                            HStack {
                                Text("应用和工具")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding([.horizontal, .top], 10)
                            
                            // 应用结果列表
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.displayResults.enumerated()), id: \.element.id) { index, result in
                                    ResultRowView(
                                        result: result,
                                        isSelected: viewModel.selectedIndex == index
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedIndex = index
                                        viewModel.handleItemClick(result)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                        .cornerRadius(8)
                        .padding(.horizontal, 8)
                    }
                    
                    // 3. 文件搜索视图 - 可折叠/展开
                    if !viewModel.searchText.isEmpty {
                        VStack(spacing: 0) {
                            // 文件搜索折叠标题栏
                            Button(action: {
                                viewModel.toggleFileSearch()
                            }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.secondary)
                                    Text("文件搜索")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: viewModel.fileSearchExpanded ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                            .cornerRadius(8)
                            
                            // 文件搜索内容 - 当展开时显示
                            if viewModel.fileSearchExpanded {
                                FileSearchView(
                                    searchService: viewModel.searchService,
                                    searchText: $viewModel.searchText,
                                    selectedIndex: $viewModel.selectedFileIndex,
                                    onResultSelected: { result in
                                        viewModel.searchService.executeResult(result)
                                    },
                                    onResultsChanged: {}
                                )
                                .padding(.horizontal, 4)
                                .padding(.top, 4)
                                .transition(.opacity)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 600)
        }
        .frame(width: 680, height: min(700, 60 + calculateContentHeight()))
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            setupKeyboardHandling()
        }
        .onChange(of: viewModel.searchText, perform: { value in
            updateHeight()
            // 自动触发搜索
            debouncer.debounce {
                viewModel.updateSearchResults(for: value)
            }
        })
        .onChange(of: viewModel.aiResponseExpanded, perform: { value in
            updateHeight()
        })
        .onChange(of: viewModel.fileSearchExpanded, perform: { value in
            updateHeight()
        })
        .onChange(of: scenePhase, perform: { value in
            if value == .active {
                viewModel.requestFocus()
            }
        })
    }
    
    // 计算内容总高度的方法
    private func calculateContentHeight() -> CGFloat {
        var totalHeight: CGFloat = 0
        
        // 基础内边距
        totalHeight += 16 // 顶部和底部各8点
        
        // AI视图高度
        if viewModel.aiResponseExpanded {
            totalHeight += 250 // AI展开时的预估高度
        } else if viewModel.shouldShowAIOption && !viewModel.searchText.isEmpty {
            totalHeight += 40 // AI折叠标题栏高度
        }
        
        // 应用程序结果高度
        if !viewModel.displayResults.isEmpty {
            let itemsHeight = CGFloat(viewModel.displayResults.count) * 48 // 每项高度48
            totalHeight += min(itemsHeight + 40, 300) // 标题栏高度 + 内容高度，不超过300
        }
        
        // 文件搜索视图高度
        if viewModel.fileSearchExpanded {
            totalHeight += 200 // 文件搜索展开时的预估高度
        } else if !viewModel.searchText.isEmpty {
            totalHeight += 40 // 文件搜索折叠标题栏高度
        }
        
        return totalHeight
    }
    
    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = KeyboardHandler.handleKeyDown(
                event: event,
                onEscape: {
                    if viewModel.aiResponseExpanded {
                        viewModel.toggleAIResponse()
                    } else if viewModel.fileSearchExpanded {
                        viewModel.toggleFileSearch()
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
                    handleArrowUp()
                },
                onArrowDown: {
                    handleArrowDown()
                }
            )
            
            return handled ? nil : event
        }
    }
    
    // 处理向上箭头键 - 统一管理所有视图的选择
    private func handleArrowUp() {
        if viewModel.fileSearchExpanded {
            // 文件搜索视图中的向上导航
            if let currentIndex = viewModel.selectedFileIndex {
                viewModel.selectedFileIndex = max(currentIndex - 1, 0)
            } else if !viewModel.searchService.fileSearchResults.isEmpty {
                viewModel.selectedFileIndex = 0
            }
        } else if viewModel.aiResponseExpanded {
            // AI响应视图中的向上导航 - 目前不需要特殊处理
        } else {
            // 主搜索结果列表中的向上导航
            if viewModel.displayResults.isEmpty { return }
            
            if let currentIndex = viewModel.selectedIndex {
                viewModel.selectedIndex = max(currentIndex - 1, 0)
            } else {
                viewModel.selectedIndex = 0
            }
        }
    }
    
    // 处理向下箭头键 - 统一管理所有视图的选择
    private func handleArrowDown() {
        if viewModel.fileSearchExpanded {
            // 文件搜索视图中的向下导航
            let fileResults = viewModel.searchService.fileSearchResults
            if fileResults.isEmpty { return }
            
            if let currentIndex = viewModel.selectedFileIndex {
                viewModel.selectedFileIndex = min(currentIndex + 1, fileResults.count - 1)
            } else {
                viewModel.selectedFileIndex = 0
            }
        } else if viewModel.aiResponseExpanded {
            // AI响应视图中的向下导航 - 目前不需要特殊处理
        } else {
            // 主搜索结果列表中的向下导航
            if viewModel.displayResults.isEmpty { return }
            
            if let currentIndex = viewModel.selectedIndex {
                viewModel.selectedIndex = min(currentIndex + 1, viewModel.displayResults.count - 1)
            } else {
                viewModel.selectedIndex = 0
            }
        }
    }
    
    func requestFocus() {
        viewModel.requestFocus()
    }
    
    func resetSearch() {
        viewModel.resetSearch()
    }
    
    private func updateHeight() {
        // 触发高度计算和更新
        let newHeight = calculateContentHeight()
        WindowCoordinator.shared.updateWindowHeight(to: 60 + newHeight, animated: true)
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