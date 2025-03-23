import SwiftUI
import AppKit
import Foundation

// 删除无搜索结果视图，使用简单的空白状态
// 删除NoResultsView结构体

struct SpotlightView: View {
    @StateObject private var viewModel: SpotlightViewModel
    @Environment(\.scenePhase) var scenePhase
    private let debouncer = Debouncer(delay: 0.3)
    
    // 控制模块选中状态
    @State private var selectedModule: SearchModule = .none
    
    // 定义搜索模块类型
    enum SearchModule: Equatable {
        case none
        case ai
        case app(Int) // 带有应用索引
        case file
        case fileResult(Int) // 带有文件结果索引
        
        // 实现Equatable协议
        static func == (lhs: SearchModule, rhs: SearchModule) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case (.ai, .ai):
                return true
            case (.file, .file):
                return true
            case let (.app(leftIndex), .app(rightIndex)):
                return leftIndex == rightIndex
            case let (.fileResult(leftIndex), .fileResult(rightIndex)):
                return leftIndex == rightIndex
            default:
                return false
            }
        }
    }
    
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
                    selectedModule = .none
                }
            )
            .frame(height: 60)
            
            // 统一的扁平化滚动视图
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // AI 模块
                    if viewModel.shouldShowAIOption && !viewModel.searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            // 标题
                            Text("AI")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            
                            // 可选中的行
                            Button(action: {
                                // 当用户点击AI行时
                                if viewModel.aiResponseExpanded {
                                    // 如果AI已经展开且搜索文本已更改，则重新发起请求
                                    if viewModel.prompt != viewModel.searchText {
                                        viewModel.prompt = viewModel.searchText
                                        viewModel.sendAIRequest()
                                    }
                                } else {
                                    // 首次展开AI响应
                                    viewModel.toggleAIResponse()
                                }
                                selectedModule = .ai
                            }) {
                                HStack {
                                    Text("问：\(viewModel.searchText)")
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .font(.body)
                                    Spacer()
                                    
                                    // 直接在行中显示加载指示器
                                    if viewModel.isAILoading {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 16, height: 16)
                                    } else if viewModel.aiResponseExpanded {
                                        Image(systemName: "chevron.up")
                                            .foregroundColor(.secondary)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .background(selectedModule == .ai ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // AI响应内容 - 展开时显示
                            if viewModel.aiResponseExpanded {
                                AIResponseView(
                                    aiService: viewModel.aiService,
                                    prompt: viewModel.prompt,
                                    onEscape: {
                                        viewModel.toggleAIResponse()
                                        selectedModule = .none
                                    },
                                    onHeightChange: { _ in }
                                )
                                .padding(.top, 4)
                                .transition(.opacity)
                                .id(viewModel.prompt) // 添加ID，确保搜索文本变化时视图会重新加载
                            }
                        }
                    }
                    
                    // 应用模块 - 只在有结果时显示
                    if !viewModel.displayResults.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            // 标题
                            Text("应用")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            
                            // 应用结果
                            ForEach(Array(viewModel.displayResults.enumerated()), id: \.element.id) { index, result in
                                Button(action: {
                                    selectedModule = .app(index)
                                    viewModel.selectedIndex = index
                                    viewModel.handleItemClick(result)
                                }) {
                                    ResultRowView(
                                        result: result,
                                        isSelected: selectedModule == .app(index)
                                    )
                                    .contentShape(Rectangle())
                                    .frame(height: 40)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .background(
                                    Group {
                                        if case .app(let idx) = selectedModule, idx == index {
                                            Color.accentColor.opacity(0.1)
                                        } else {
                                            Color.clear
                                        }
                                    }
                                )
                                .cornerRadius(6)
                            }
                        }
                    }
                    
                    // 文件搜索模块
                    if !viewModel.searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            // 标题
                            Text("文件")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            
                            // 可选中的文件搜索行
                            Button(action: {
                                viewModel.toggleFileSearch()
                                selectedModule = .file
                            }) {
                                HStack {
                                    Text("搜索：\(viewModel.searchText)")
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .font(.body)
                                    Spacer()
                                    
                                    // 加载指示器
                                    if viewModel.searchService.isSearchingFiles {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 16, height: 16)
                                    } else if viewModel.fileSearchExpanded {
                                        Image(systemName: "chevron.up")
                                            .foregroundColor(.secondary)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .background(selectedModule == .file ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // 文件搜索结果
                            if viewModel.fileSearchExpanded {
                                // 显示最多10个文件结果
                                let fileResults = viewModel.searchService.fileSearchResults
                                let displayCount = min(10, fileResults.count)
                                
                                // 文件结果列表
                                ForEach(0..<displayCount, id: \.self) { index in
                                    let result = fileResults[index]
                                    Button(action: {
                                        selectedModule = .fileResult(index)
                                        viewModel.selectedFileIndex = index
                                        viewModel.searchService.executeResult(result)
                                    }) {
                                        ResultRowView(
                                            result: result,
                                            isSelected: selectedModule == .fileResult(index)
                                        )
                                        .contentShape(Rectangle())
                                        .frame(height: 40)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .background(
                                        Group {
                                            if case .fileResult(let idx) = selectedModule, idx == index {
                                                Color.accentColor.opacity(0.1)
                                            } else {
                                                Color.clear
                                            }
                                        }
                                    )
                                    .cornerRadius(6)
                                }
                                
                                // 加载更多按钮（如果有更多结果）
                                if fileResults.count > 10 {
                                    Button(action: {
                                        // 加载更多文件结果
                                        viewModel.loadMoreFileResults()
                                    }) {
                                        HStack {
                                            Text("加载更多结果...")
                                                .foregroundColor(.secondary)
                                                .font(.body)
                                            Spacer()
                                            Image(systemName: "arrow.down.circle")
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .background(selectedModule == .file ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 0)
            }
            // 移除滚动视图内边距
            .padding(0)
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
            debouncer.run {
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
        // totalHeight += 24
        
        // AI模块高度
        if viewModel.shouldShowAIOption && !viewModel.searchText.isEmpty {
            totalHeight += 30 // 标题高度
            totalHeight += 40 // 问题行高度
            
            // AI响应展开高度
            if viewModel.aiResponseExpanded {
                totalHeight += 250 // AI展开时的预估高度
            }
        }
        
        // 应用模块高度
        if !viewModel.displayResults.isEmpty {
            totalHeight += 30 // 标题高度
            totalHeight += CGFloat(viewModel.displayResults.count) * 48 // 每项高度48
        }
        
        // 文件模块高度
        if !viewModel.searchText.isEmpty {
            totalHeight += 30 // 标题高度
            totalHeight += 40 // 搜索行高度
            
            // 文件搜索展开高度
            if viewModel.fileSearchExpanded {
                let fileResultCount = min(10, viewModel.searchService.fileSearchResults.count)
                totalHeight += CGFloat(fileResultCount) * 48 // 每项高度48
                
                // 加载更多按钮
                if viewModel.searchService.fileSearchResults.count > 10 {
                    totalHeight += 40
                }
            }
        }
        
        return totalHeight
    }
    
    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = KeyboardHandler.handleKeyDown(
                event: event,
                onEscape: handleEscape,
                onEnter: handleEnter,
                onArrowUp: handleArrowUp,
                onArrowDown: handleArrowDown
            )
            
            return handled ? nil : event
        }
    }
    
    // 处理ESC键
    private func handleEscape() {
        if viewModel.aiResponseExpanded || viewModel.fileSearchExpanded {
            // 如果有展开的面板，先关闭面板
            if viewModel.aiResponseExpanded {
                viewModel.toggleAIResponse()
            }
            if viewModel.fileSearchExpanded {
                viewModel.toggleFileSearch()
            }
            selectedModule = .none
        } else if !viewModel.searchText.isEmpty {
            // 如果搜索栏有内容，清空搜索
            viewModel.resetSearch()
            selectedModule = .none
        } else {
            // 完全退出
            NSApp.hide(nil)
        }
    }
    
    // 处理回车键
    private func handleEnter() {
        switch selectedModule {
        case .none:
            if !viewModel.displayResults.isEmpty {
                // 如果有应用结果但没有选中模块，自动选择第一个应用
                selectedModule = .app(0)
                viewModel.selectedIndex = 0
                if let result = viewModel.displayResults.first {
                    viewModel.handleItemClick(result)
                }
            } else if viewModel.shouldShowAIOption {
                // 如果没有应用结果但显示AI选项，选择AI
                selectedModule = .ai
                if viewModel.aiResponseExpanded {
                    // 如果AI对话已展开且搜索文本已更改，发起新请求
                    if viewModel.prompt != viewModel.searchText {
                        viewModel.prompt = viewModel.searchText
                        viewModel.sendAIRequest()
                    }
                } else {
                    // 否则切换展开状态
                    viewModel.toggleAIResponse()
                }
            } else if !viewModel.searchText.isEmpty {
                // 如果以上都没有但有搜索文本，选择文件搜索
                selectedModule = .file
                viewModel.toggleFileSearch()
            }
            
        case .ai:
            // 如果AI已选中
            if viewModel.aiResponseExpanded {
                // 如果已展开且搜索文本已更改，发起新请求
                if viewModel.prompt != viewModel.searchText {
                    viewModel.prompt = viewModel.searchText
                    viewModel.sendAIRequest()
                }
            } else {
                // 否则切换展开状态
                viewModel.toggleAIResponse()
            }
            
        case .app(let index):
            // 执行应用点击
            if index >= 0 && index < viewModel.displayResults.count {
                let result = viewModel.displayResults[index]
                viewModel.handleItemClick(result)
            }
            
        case .file:
            // 切换文件搜索的展开状态
            viewModel.toggleFileSearch()
            
        case .fileResult(let index):
            // 执行文件结果点击
            let fileResults = viewModel.searchService.fileSearchResults
            if index >= 0 && index < fileResults.count {
                let result = fileResults[index]
                viewModel.searchService.executeResult(result)
            }
        }
    }
    
    // 处理向上箭头键
    private func handleArrowUp() {
        switch selectedModule {
        case .none:
            // 无选择时，选择最后一个可用模块
            if !viewModel.displayResults.isEmpty {
                let lastIndex = viewModel.displayResults.count - 1
                selectedModule = .app(lastIndex)
                viewModel.selectedIndex = lastIndex
            } else if viewModel.shouldShowAIOption {
                selectedModule = .ai
            } else if !viewModel.searchText.isEmpty {
                selectedModule = .file
            }
            
        case .ai:
            // AI已经是最顶部，不做操作
            break
            
        case .app(let index):
            if index > 0 {
                // 移动到上一个应用
                selectedModule = .app(index - 1)
                viewModel.selectedIndex = index - 1
            } else if viewModel.shouldShowAIOption {
                // 如果是第一个应用，移动到AI
                selectedModule = .ai
            }
            
        case .file:
            // 如果有应用结果，移动到最后一个应用
            if !viewModel.displayResults.isEmpty {
                let lastIndex = viewModel.displayResults.count - 1
                selectedModule = .app(lastIndex)
                viewModel.selectedIndex = lastIndex
            } else if viewModel.shouldShowAIOption {
                // 如果没有应用但有AI，移动到AI
                selectedModule = .ai
            }
            
        case .fileResult(let index):
            if viewModel.fileSearchExpanded {
                if index > 0 {
                    // 移动到上一个文件结果
                    selectedModule = .fileResult(index - 1)
                    viewModel.selectedFileIndex = index - 1
                } else {
                    // 如果是第一个文件结果，移动到文件搜索行
                    selectedModule = .file
                }
            }
        }
    }
    
    // 处理向下箭头键
    private func handleArrowDown() {
        switch selectedModule {
        case .none:
            // 无选择时，选择第一个可用模块
            if viewModel.shouldShowAIOption {
                selectedModule = .ai
            } else if !viewModel.displayResults.isEmpty {
                selectedModule = .app(0)
                viewModel.selectedIndex = 0
            } else if !viewModel.searchText.isEmpty {
                selectedModule = .file
            }
            
        case .ai:
            // 从AI向下移动到应用（如果有）
            if !viewModel.displayResults.isEmpty {
                selectedModule = .app(0)
                viewModel.selectedIndex = 0
            } else if !viewModel.searchText.isEmpty {
                // 如果没有应用但有文件搜索，移动到文件搜索
                selectedModule = .file
            }
            
        case .app(let index):
            if index < viewModel.displayResults.count - 1 {
                // 移动到下一个应用
                selectedModule = .app(index + 1)
                viewModel.selectedIndex = index + 1
            } else if !viewModel.searchText.isEmpty {
                // 如果是最后一个应用，移动到文件搜索
                selectedModule = .file
            }
            
        case .file:
            // 如果文件搜索已展开且有结果，移动到第一个文件结果
            if viewModel.fileSearchExpanded && !viewModel.searchService.fileSearchResults.isEmpty {
                selectedModule = .fileResult(0)
                viewModel.selectedFileIndex = 0
            }
            
        case .fileResult(let index):
            if viewModel.fileSearchExpanded {
                let fileResults = viewModel.searchService.fileSearchResults
                let displayCount = min(10, fileResults.count)
                
                if index < displayCount - 1 {
                    // 移动到下一个文件结果
                    selectedModule = .fileResult(index + 1)
                    viewModel.selectedFileIndex = index + 1
                }
                // 如果是最后一个且有更多结果可加载，保持在最后一个（加载更多按钮）
            }
        }
    }
    
    private func updateHeight() {
        // 触发高度计算和更新
        let newHeight = calculateContentHeight()
        WindowCoordinator.shared.updateWindowHeight(to: 60 + newHeight, animated: true)
    }
    
    func requestFocus() {
        viewModel.requestFocus()
    }
    
    func resetSearch() {
        viewModel.resetSearch()
        selectedModule = .none
    }
}

// 保留原有的支持组件代码
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