import SwiftUI
import Combine

// 定义视图模式枚举，便于管理不同状态下的高度调整
enum ViewMode {
    case search // 普通搜索模式
    case fileSearch // 文件搜索模式 
    case aiResponse // AI回复模式
    
    // 每种模式的基础高度（不包含内容）
    var baseHeight: CGFloat {
        return 60 // 搜索框高度在所有模式下都是60
    }
    
    // 每种模式的最小内容高度
    var minContentHeight: CGFloat {
        switch self {
        case .search: return 0
        case .fileSearch: return 100
        case .aiResponse: return 250
        }
    }
    
    // 每种模式的最大内容高度
    var maxContentHeight: CGFloat {
        switch self {
        case .search: return 300
        case .fileSearch: return 300
        case .aiResponse: return 500
        }
    }
}

@MainActor
class SpotlightViewModel: ObservableObject {
    // 搜索状态
    @Published var searchText = ""
    @Published var selectedIndex: Int?
    @Published var showingAIResponse = false
    @Published var showingFileSearch = false
    @Published var height: CGFloat = 60
    @Published var prompt: String = ""
    
    // 当前内容高度（不包括搜索框）
    @Published var contentHeight: CGFloat = 0
    
    // 当前视图模式
    var currentMode: ViewMode {
        if showingAIResponse {
            return .aiResponse
        } else if showingFileSearch {
            return .fileSearch
        } else {
            return .search
        }
    }
    
    let searchService: SearchService
    let aiService: AIService
    private var cancellables = Set<AnyCancellable>()
    
    var shouldShowAIOption: Bool {
        searchText.count >= 3
    }
    
    // 计算显示结果，将特殊入口和搜索结果合并
    var displayResults: [SearchResult] {
        var results: [SearchResult] = []
        
        // AI入口
        if shouldShowAIOption {
            let aiResult = SearchResult(
                id: UUID(),
                name: "Ask AI: \(searchText)",
                path: "",
                type: .ai,
                category: "AI",
                icon: NSImage(systemSymbolName: "brain.fill", accessibilityDescription: nil) ?? NSImage(),
                subtitle: "使用 AI 回答问题"
            )
            results.append(aiResult)
        }
        
        // 添加搜索结果
        results.append(contentsOf: searchService.searchResults)
        
        // 文件搜索入口
        if !searchText.isEmpty {
            let fileSearchResult = SearchResult(
                id: UUID(),
                name: "搜索文件: \(searchText)",
                path: "",
                type: .file,
                category: "文件搜索",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                subtitle: "搜索本地文件"
            )
            results.append(fileSearchResult)
        }
        
        print("计算显示结果：总数 \(results.count)")
        return results
    }
    
    init(searchService: SearchService, aiService: AIService) {
        self.searchService = searchService
        self.aiService = aiService
        
        // 设置搜索文本变化响应
        $searchText
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] text in
                print("搜索文本变化: \"\(text)\"")
                self?.performSearch(text: text)
            }
            .store(in: &cancellables)
        
        // 统一监听会影响显示结果的所有状态变化
        Publishers.CombineLatest3(
            $searchText,
            searchService.$searchResults,
            $showingFileSearch
        )
        .filter { _, _, showingFileSearch in
            // 仅在非文件搜索模式下才更新常规搜索高度
            return !showingFileSearch
        }
        .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _ in
            guard let self = self, !self.showingAIResponse else { return }
            self.updateSearchResultsHeight()
        }
        .store(in: &cancellables)
            
        // 监听文件搜索结果变化
        searchService.$fileSearchResults
            .filter { [weak self] _ in
                // 仅在文件搜索模式下更新文件搜索高度
                return self?.showingFileSearch == true
            }
            .sink { [weak self] results in
                guard let self = self else { return }
                self.updateFileSearchResultsHeight(results)
            }
            .store(in: &cancellables)
            
        // 监听视图模式变化
        Publishers.CombineLatest($showingAIResponse, $showingFileSearch)
            .sink { [weak self] (showingAI, showingFile) in
                guard let self = self else { return }
                print("模式变化: AI=\(showingAI), 文件=\(showingFile)")
                
                // 模式切换时重置内容高度
                if showingAI {
                    // AI视图模式
                    self.updateContentHeight(250) // AI视图初始高度
                } else if showingFile {
                    // 文件搜索模式
                    self.updateFileSearchResultsHeight(self.searchService.fileSearchResults)
                } else {
                    // 常规搜索模式
                    self.updateSearchResultsHeight()
                }
            }
            .store(in: &cancellables)
    }
    
    // 更新普通搜索结果高度
    private func updateSearchResultsHeight() {
        let results = displayResults
        print("更新搜索结果高度: 结果数 \(results.count)")
        
        if results.isEmpty {
            print("无搜索结果，设置高度为0")
            updateContentHeight(0)
        } else {
            let rowHeight: CGFloat = 48
            let padding: CGFloat = 16
            let calculatedHeight = min(CGFloat(results.count) * rowHeight + padding, 300)
            print("计算搜索高度: \(calculatedHeight)，基于 \(results.count) 项")
            updateContentHeight(calculatedHeight)
        }
    }
    
    // 更新文件搜索结果高度
    private func updateFileSearchResultsHeight(_ results: [SearchResult]) {
        print("更新文件搜索高度: 结果数 \(results.count)")
        
        if results.isEmpty {
            print("无文件搜索结果，设置最小高度")
            updateContentHeight(100) // 空结果最小高度
        } else {
            let rowHeight: CGFloat = 48
            let padding: CGFloat = 16
            let calculatedHeight = min(CGFloat(results.count) * rowHeight + padding, 300)
            print("计算文件搜索高度: \(calculatedHeight)，基于 \(results.count) 项")
            updateContentHeight(calculatedHeight)
        }
    }
    
    // 统一的内容高度更新方法
    func updateContentHeight(_ newContentHeight: CGFloat) {
        let mode = self.currentMode
        let clampedHeight = min(max(newContentHeight, mode.minContentHeight), mode.maxContentHeight)
        
        // 避免频繁微小变化导致的不必要更新
        if abs(self.contentHeight - clampedHeight) > 1 {
            print("设置最终高度: \(clampedHeight)，总高度: \(mode.baseHeight + clampedHeight)")
            
            // 在主线程上同步执行高度更新，确保状态同步
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.contentHeight = clampedHeight
                self.height = mode.baseHeight + clampedHeight
                WindowSizeManager.adjustWindowHeight(for: self.height)
            }
        }
    }
    
    func performSearch(text: String) {
        // 非AI或文件搜索模式时执行搜索
        if !showingAIResponse && !showingFileSearch {
            print("执行搜索: \"\(text)\"")
            
            // 搜索前先清空结果，避免旧结果残留
            if searchService.searchResults.count > 0 {
                searchService.clearResults()
            }
            
            // 执行新搜索
            searchService.search(query: text)
            
            // 更新选中状态
            selectedIndex = text.isEmpty ? nil : 0
            UserDefaults.standard.set(text, forKey: "LastSearchText")
            
            // 空搜索时立即重置高度
            if text.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    print("空搜索，立即重置高度")
                    self.contentHeight = 0
                    self.height = 60
                    WindowSizeManager.resetWindowHeight()
                }
            }
        }
    }
    
    func handleItemClick(_ result: SearchResult) {
        switch result.type {
        case .ai:
            // 先清空现有结果，避免在切换到AI视图后仍显示
            searchService.clearResults()
            
            // 设置状态
            prompt = searchText
            showingAIResponse = true
            selectedIndex = nil
            
            // AI请求将在视图加载时自动启动
            
        case .file:
            // 先清空现有结果，避免在切换到文件搜索视图后仍显示
            searchService.clearResults()
            
            // 设置状态
            showingFileSearch = true
            selectedIndex = nil
            
            // 执行文件搜索
            searchService.searchFiles(query: searchText)
            
        default:
            searchService.executeResult(result)
        }
    }
    
    func handleSubmit() {
        if showingAIResponse {
            // 在AI视图中按提交键，应直接发送当前问题
            Task {
                print("在AI视图中提交问题: \(searchText)")
                await aiService.streamChat(prompt: searchText)
            }
        } else if let index = selectedIndex, index < displayResults.count {
            // 在搜索结果中选择一项
            handleItemClick(displayResults[index])
        }
    }
    
    // 直接设置AI内容高度的方法（供AIResponseView调用）
    func setAIContentHeight(_ height: CGFloat) {
        if showingAIResponse {
            print("更新AI内容高度: \(height)")
            updateContentHeight(height)
        }
    }
    
    func resetSearch() {
        print("重置所有搜索状态")
        
        // 先确保所有搜索结果都被清空，防止残留
        searchService.clearResults()
        searchService.fileSearchResults = []
        
        // 在主线程上同步执行UI状态更新
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 重置搜索状态
            self.searchText = ""
            self.selectedIndex = nil
            self.showingAIResponse = false
            self.showingFileSearch = false
            
            // 重置高度状态
            self.contentHeight = 0
            self.height = 60
            
            // 调整窗口大小
            WindowSizeManager.resetWindowHeight()
        }
    }
    
    func requestFocus() {
        // 通过NotificationCenter发送请求焦点通知
        NotificationCenter.default.post(name: Notification.Name("RequestSearchFocus"), object: nil)
    }
    
    // 从AI或文件搜索视图返回
    func exitCurrentMode() {
        print("退出当前模式: \(currentMode)")
        
        // 记住当前搜索文本
        let currentText = searchText
        
        // 必须先重置搜索状态，再重新执行搜索
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 清空所有搜索结果
            self.searchService.fileSearchResults = []
            self.searchService.searchResults = []
            
            // 2. 重置视图状态
            self.showingAIResponse = false
            self.showingFileSearch = false
            
            // 3. 重置高度（避免从大高度突然变小导致UI闪烁）
            self.contentHeight = 0
            self.height = 60
            WindowSizeManager.resetWindowHeight()
            
            // 4. 重新执行搜索，这将触发高度重新计算
            self.performSearch(text: currentText)
        }
    }
} 