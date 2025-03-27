import SwiftUI
import Combine

// 重新定义ViewMode类型
enum ViewMode {
    case search     // 普通搜索模式
    case fileSearch // 文件搜索模式 
    case aiResponse // AI回复模式
    case mixed      // 混合模式，同时显示多个视图
}

// 定义搜索视图模型，负责管理搜索状态和结果
@MainActor
class SpotlightViewModel: ObservableObject {
    // 搜索状态
    @Published var searchText = ""
    @Published var selectedModuleIndex: Int?
    @Published var selectedIndex: Int?
    @Published var selectedFileIndex: Int? // 文件搜索结果的专用索引
    
    // 视图状态变量
    @Published var aiResponseExpanded = false // AI响应是否展开
    @Published var fileSearchExpanded = false // 文件搜索是否展开
    @Published var prompt: String = ""
    
    // 标记搜索中状态
    @Published var isSearching = false
    @Published var isAILoading = false
    
    // 文件搜索结果分页状态
    @Published var fileResultsPage: Int = 0
    
    // 缓存的显示结果，避免重复计算
    private var _cachedDisplayResults: [SearchResult] = []
    
    // 搜索服务和AI服务
    let searchService: SearchService
    let aiService: AIService
    private var cancellables = Set<AnyCancellable>()
    
    // 计算属性 - 判断是否应该显示AI选项
    var shouldShowAIOption: Bool {
        searchText.count >= 3
    }
    
    // 显示结果 - 只包含应用和快捷方式
    var displayResults: [SearchResult] {
        return _cachedDisplayResults.filter { $0.type == .application || $0.type == .shortcut }
    }
    
    var displayFileResults: [SearchResult] {
        return _cachedDisplayResults.filter { $0.type == .file }
    }
    
    init(searchService: SearchService, aiService: AIService) {
        self.searchService = searchService
        self.aiService = aiService
        
        // 初始化并配置发布者
        setupPublishers()
    }
    
    // 单一集中的发布者设置
    private func setupPublishers() {
        // 取消任何现有订阅
        cancellables.removeAll()
        
        // 搜索文本变更发布者
        $searchText
            .dropFirst()  // 忽略初始值
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self = self else { return }

                // 更新搜索结果
                self.updateSearchResults(for: text)
                
            }
            .store(in: &cancellables)
        
        // 监听搜索服务结果变化
        searchService.$searchResults
            .sink { [weak self] results in
                guard let self = self else { return }
                // 更新缓存的结果
                self.handleSearchResultsUpdated(results)
            }
            .store(in: &cancellables)
        
        // 监听文件搜索结果变化
        searchService.$fileSearchResults
            .sink { [weak self] results in
                guard let self = self else { return }
                print("【搜索结果】文件搜索完成，获得\(results.count)个结果")
                
                // 如果有结果且未选定项，则自动选中第一项
                if !results.isEmpty && self.selectedFileIndex == nil && self.fileSearchExpanded {
                    self.selectedFileIndex = 0
                }
            }
            .store(in: &cancellables)
    }
    
    // 更新搜索结果
    func updateSearchResults(for text: String) {
        // 标记搜索开始
        isSearching = true
        
        // 对搜索文本进行trim处理
        let trimmedText = text.trim()
        
        // 空搜索直接处理
        if trimmedText.isEmpty {
            if !_cachedDisplayResults.isEmpty {
                DispatchQueue.main.async { [self] in
                    // 重置搜索状态
                    self.resetSearch()
                }
            }
            return
        }
        
        // 正常搜索处理
        Task { @MainActor in
            // 执行搜索并等待结果
            self.searchService.search(query: trimmedText)
            // 当搜索文本变化时，自动执行文件搜索（如果文件搜索已展开）
            if self.fileSearchExpanded {
                Task {
                    self.searchService.searchFiles(query: trimmedText)
                }
            }
        }
    }
    
    // 处理搜索结果更新
    private func handleSearchResultsUpdated(_ results: [SearchResult]) {
        // 搜索完成，清除搜索中状态
        isSearching = false
        
        // 创建标准化的结果集
        var entries: [SearchResult] = []
        
        // 添加应用搜索结果
        if !results.isEmpty {
            entries.append(contentsOf: results)
        }
        
        // 批量更新视图状态
        DispatchQueue.main.async { [self] in
            // 更新缓存
            self._cachedDisplayResults = entries
            
            // 确保有结果时选中第一项
            if !entries.isEmpty {
                self.selectedIndex = 0
            }
        }
    }
    
    // 处理点击搜索结果项
    func handleItemClick(_ result: SearchResult) {
        searchService.executeResult(result)
    }
    
    // 切换AI响应的展开/折叠状态
    func toggleAIResponse() {
        // 首次展开时，记录当前搜索文本作为prompt
        if !aiResponseExpanded && !searchText.isEmpty {
            prompt = searchText
            sendAIRequest()
        }
        
        withAnimation {
            aiResponseExpanded.toggle()
            if !aiResponseExpanded {
                // 关闭时取消所有AI请求
                aiService.cancelRequests()
                isAILoading = false
            }
        }
    }
    
    // 发送AI请求
    func sendAIRequest() {
        guard !prompt.isEmpty else { return }
        
        isAILoading = true
        
        Task {
            await aiService.sendRequest(prompt: prompt.trim())
            await MainActor.run {
                isAILoading = false
            }
        }
    }
    
    // 切换文件搜索的展开/折叠状态
    func toggleFileSearch() {
        fileSearchExpanded.toggle()
        
        if fileSearchExpanded {
            // 展开文件搜索时开始执行搜索
            Task {
                searchService.searchFiles(query: searchText)
            }
        } else {
            // 折叠时清理文件搜索状态
            selectedFileIndex = nil
        }
        
        // 重新聚焦到搜索框
        requestFocus()
    }
    
    // 处理提交搜索、发起AI请求
    func handleSubmit() {
        if aiResponseExpanded {
            // 如果AI面板已经展开，向AI提交查询
            prompt = searchText
            
            // 设置加载状态
            isAILoading = true
            
            // 执行AI查询
            Task {
                do {
                    try await aiService.sendQuery(prompt)
                    
                    // 完成后更新状态
                    await MainActor.run {
                        isAILoading = false
                    }
                } catch {
                    // 错误处理
                    await MainActor.run {
                        isAILoading = false
                        // 可以添加错误提示
                    }
                }
            }
        } else if selectedIndex != nil {
            // 如果已经选中搜索结果，执行选中项
            if let index = selectedIndex, index < displayResults.count {
                let result = displayResults[index]
                handleItemClick(result)
            }
        } else if fileSearchExpanded && selectedFileIndex != nil {
            // 如果文件搜索已展开且选中了文件结果
            if let index = selectedFileIndex, index < searchService.fileSearchResults.count {
                let result = searchService.fileSearchResults[index]
                searchService.executeResult(result)
            }
        }
    }
    
    func clearSearchText() {
        self.searchText = ""
    }
    
    // 重置搜索
    func resetSearch() {
        print("重置所有搜索状态")
        
        // 批量更新UI状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 先确保所有搜索结果都被清空
            searchService.clearResults()
            // 重置搜索状态
            self.selectedIndex = nil
            self.selectedFileIndex = nil
            self.aiResponseExpanded = false
            self.fileSearchExpanded = false
            
            // 重置缓存结果
            self._cachedDisplayResults = []
        }
    }
    
    // 请求焦点
    func requestFocus() {
        // 通过NotificationCenter发送请求焦点通知
        NotificationCenter.default.post(name: Notification.Name("RequestSearchFocus"), object: nil)
    }
    
    // 加载更多文件结果
    func loadMoreFileResults() {
        fileResultsPage += 1
        // 实现加载更多文件结果的逻辑
        Task {
            await searchService.searchMoreFiles(query: searchText, page: fileResultsPage)
        }
    }
}
