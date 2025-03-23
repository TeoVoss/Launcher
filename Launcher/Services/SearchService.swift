import Foundation
import AppKit
import Combine

// 搜索服务 - 对外提供统一接口，内部委托给专门的搜索服务
class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var fileSearchResults: [SearchResult] = []
    @Published var isSearchingFiles: Bool = false
    
    private let searchResultManager: SearchResultManager
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 初始化搜索结果管理器
        self.searchResultManager = SearchResultManager()
        
        // 订阅管理器的结果
        setupSubscriptions()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    private func setupSubscriptions() {
        // 订阅搜索结果更新
        searchResultManager.$searchResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                self?.searchResults = results
            }
            .store(in: &cancellables)
        
        // 订阅分类结果更新
        searchResultManager.$categories
            .receive(on: RunLoop.main)
            .sink { [weak self] categories in
                self?.categories = categories
                
                // 更新文件搜索结果 - 保持兼容性
                let fileResults = categories.first(where: { $0.title == "最近文件" })?.results ?? []
                let nonSystemApps = categories.first(where: { $0.title == "其他应用程序" })?.results ?? []
                self?.fileSearchResults = nonSystemApps + fileResults
            }
            .store(in: &cancellables)
    }
    
    // 保持与原有API兼容的搜索方法
    func search(query: String) {
        searchResultManager.search(query: query)
    }
    
    // 保持与原有API兼容的文件搜索方法
    func searchFiles(query: String) {
        // 如果查询为空，则直接清除文件搜索结果
        if query.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.fileSearchResults = []
                self?.isSearchingFiles = false
            }
            searchResultManager.clearFileResults()
            return
        }
        
        // 设置搜索中状态
        DispatchQueue.main.async { [weak self] in
            self?.isSearchingFiles = true
        }
        
        // 专门执行文件搜索
        searchResultManager.searchFiles(query: query)
        
        // 搜索完成后更新状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isSearchingFiles = false
        }
    }
    
    // 保持与原有API兼容的打开结果方法
    func openResult(_ result: SearchResult) {
        searchResultManager.openResult(result)
    }
    
    // 执行搜索结果的方法 - 与openResult相同
    func executeResult(_ result: SearchResult) {
        searchResultManager.openResult(result)
    }
    
    // 保持与原有API兼容的清除结果方法
    func clearResults() {
        searchResultManager.clearResults()
        // 同时确保文件搜索结果也被清除
        DispatchQueue.main.async { [weak self] in
            self?.fileSearchResults = []
        }
    }
    
    // 清空所有类型的搜索结果 - 用于彻底重置搜索状态
    func clearAllResults() {
        // 清空结果管理器中的所有结果
        searchResultManager.clearResults()
        searchResultManager.clearFileResults()
        
        // 确保UI状态同步更新
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.searchResults = []
            self.fileSearchResults = []
            self.categories = []
            self.isSearchingFiles = false
        }
    }
    
    // 清除文件搜索结果 - 用于退出文件搜索模式时清理状态
    func clearFileSearchResults() {
        // 只清除文件相关结果，保留普通搜索结果
        searchResultManager.clearFileResults()
        
        // 确保UI状态同步更新
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fileSearchResults = []
            self.isSearchingFiles = false
        }
    }
    
    // 添加分页搜索文件的方法
    @MainActor
    func searchMoreFiles(query: String, page: Int) async {
        // 标记搜索开始
        isSearchingFiles = true
        
        // 获取当前页范围
        let pageSize = 10
        let startIndex = page * pageSize
        
        // 复用现有的文件搜索功能
        let newResults = await FileSearchService.searchFiles(query: query, startIndex: startIndex, limit: pageSize)
        
        // 将新结果添加到现有结果中
        if !newResults.isEmpty {
            let allResults = fileSearchResults + newResults
            // 更新结果，避免重复
            let uniqueResults = Array(Set(allResults))
            fileSearchResults = uniqueResults.sorted(by: { $0.name < $1.name })
        }
        
        // 标记搜索结束
        isSearchingFiles = false
    }
} 