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
    @Published var selectedIndex: Int?
    @Published var selectedFileIndex: Int? // 文件搜索结果的专用索引
    
    // 视图状态变量
    @Published var aiResponseExpanded = false // AI响应是否展开
    @Published var fileSearchExpanded = false // 文件搜索是否展开
    @Published var prompt: String = ""
    
    // 标记搜索中状态
    @Published var isSearching = false
    
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
    
    // 显示结果 - 排除特殊类型
    var displayResults: [SearchResult] {
        return _cachedDisplayResults.filter { $0.type != .ai && $0.type != .file }
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
                
                // 当搜索文本变化时，自动执行文件搜索（如果文件搜索已展开）
                if !text.isEmpty && self.fileSearchExpanded {
                    Task {
                        await self.searchService.searchFiles(query: text)
                    }
                }
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
        
        // 空搜索直接处理
        if text.isEmpty {
            // 批量应用所有更改
            DispatchQueue.main.async { [self] in
                // 重置所有缓存
                self._cachedDisplayResults = []
                self.isSearching = false
                self.selectedIndex = nil
            }
            return
        }
        
        // 正常搜索处理
        Task { @MainActor in
            // 执行搜索并等待结果
            await searchService.search(query: text)
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
            if !entries.isEmpty && self.selectedIndex == nil {
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
        aiResponseExpanded.toggle()
        
        if aiResponseExpanded {
            // 展开AI响应时设置提示词并请求AI响应
            self.prompt = searchText
            Task {
                await aiService.streamChat(prompt: searchText)
            }
        } else {
            // 折叠时重置提示词
            self.prompt = ""
        }
        
        // 重新聚焦到搜索框
        requestFocus()
    }
    
    // 切换文件搜索的展开/折叠状态
    func toggleFileSearch() {
        fileSearchExpanded.toggle()
        
        if fileSearchExpanded {
            // 展开文件搜索时开始执行搜索
            Task {
                await searchService.searchFiles(query: searchText)
            }
        } else {
            // 折叠时清理文件搜索状态
            selectedFileIndex = nil
            searchService.clearFileSearchResults()
        }
        
        // 重新聚焦到搜索框
        requestFocus()
    }
    
    // 处理提交动作
    func handleSubmit() {
        if aiResponseExpanded {
            // 在AI视图中按提交键，应直接发送当前问题
            Task {
                print("在AI视图中提交问题: \(searchText)")
                await aiService.streamChat(prompt: searchText)
            }
        } else if fileSearchExpanded {
            // 在文件搜索视图中按提交键
            if let index = selectedFileIndex, 
               index < searchService.fileSearchResults.count {
                let result = searchService.fileSearchResults[index]
                searchService.executeResult(result)
            }
        } else if let index = selectedIndex, index < displayResults.count {
            // 在搜索结果中选择一项
            handleItemClick(displayResults[index])
        }
    }
    
    // 重置搜索
    func resetSearch() {
        print("重置所有搜索状态")
        
        // 先确保所有搜索结果都被清空
        searchService.clearResults()
        searchService.clearFileSearchResults()
        
        // 批量更新UI状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 重置搜索文本和状态
            self.searchText = ""
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
} 