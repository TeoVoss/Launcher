import Foundation
import AppKit
import Combine

// 搜索服务 - 对外提供统一接口，内部委托给专门的搜索服务
class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var fileResults: [SearchResult] = []
    @Published var isSearchingFiles: Bool = false
    
    private let searchResultManager: SearchResultManager
    private var cancellables = Set<AnyCancellable>()
    
    // 搜索结果缓存 - 提高频繁搜索同一内容的性能
    private var resultCache = NSCache<NSString, NSArray>()
    
    // 当前正在执行的搜索任务
    private var currentSearchTask: Task<Void, Never>? = nil
    private var currentFileSearchTask: Task<Void, Never>? = nil
    
    init() {
        // 初始化搜索结果管理器
        self.searchResultManager = SearchResultManager()
        
        // 配置缓存
        resultCache.countLimit = 20 // 最多缓存20个查询
        
        // 订阅管理器的结果
        setupSubscriptions()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        // 取消所有正在执行的任务
        currentSearchTask?.cancel()
        currentFileSearchTask?.cancel()
    }
    
    private func setupSubscriptions() {
        // 订阅搜索结果更新
        searchResultManager.$appResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                self?.searchResults = results
            }
            .store(in: &cancellables)
        searchResultManager.$fileResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                self?.fileResults = results
            }
            .store(in: &cancellables)
    }
    
    // 保持与原有API兼容的搜索方法 - 添加缓存支持
    func search(query: String) {
        // 取消之前的搜索任务
        currentSearchTask?.cancel()
        
        // 如果查询为空，则直接清除结果
        if query.isEmpty {
            return
        }
        
        // 检查缓存
        let cacheKey = NSString(string: "search_\(query)")
        if let cachedResults = resultCache.object(forKey: cacheKey) as? [SearchResult] {
            // 使用缓存的结果
            DispatchQueue.main.async { [weak self] in
                self?.searchResults = cachedResults
            }
            return
        }
        
        // 创建新的搜索任务
        currentSearchTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 执行搜索
            self.searchResultManager.search(query: query)
            
            // 等待搜索完成
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            // 如果任务没有被取消，缓存结果
            if !Task.isCancelled {
                await MainActor.run {
                    // 缓存结果
                    self.resultCache.setObject(self.searchResults as NSArray, forKey: cacheKey)
                }
            }
        }
    }
    
    // 保持与原有API兼容的文件搜索方法 - 添加缓存和并发支持
    func searchFiles(query: String) {
        // 取消之前的文件搜索任务
        currentFileSearchTask?.cancel()
        
        // 如果查询为空，则直接清除文件搜索结果
        if query.isEmpty {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.fileResults = []
                self.isSearchingFiles = false
            }
            searchResultManager.clearFileResults()
            return
        }
        
        // 检查缓存
        let cacheKey = NSString(string: "file_search_\(query)")
        if let cachedResults = resultCache.object(forKey: cacheKey) as? [SearchResult] {
            // 使用缓存的结果
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.fileResults = cachedResults
                self.isSearchingFiles = false
            }
            return
        }
        
        // 设置搜索中状态
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isSearchingFiles = true
        }
        
        // 创建新的文件搜索任务
        currentFileSearchTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 专门执行文件搜索
            self.searchResultManager.searchFiles(query: query)
            
            // 等待搜索完成
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            
            // 如果任务没有被取消，缓存结果
            if !Task.isCancelled {
                await MainActor.run {
                    // 缓存结果
                    self.resultCache.setObject(self.fileResults as NSArray, forKey: cacheKey)
                    self.isSearchingFiles = false
                }
            }
        }
    }
    
    // 执行搜索结果的方法 - 与openResult相同
    func executeResult(_ result: SearchResult) {
        searchResultManager.openResult(result)
    }
    
    // 保持与原有API兼容的清除结果方法
    func clearResults() {
        // 取消所有搜索任务
        currentSearchTask?.cancel()
        currentFileSearchTask?.cancel()
        searchResultManager.clearResults()
    }
    
    // 添加分页搜索文件的方法 - 保持原有功能
    @MainActor
    func searchMoreFiles(query: String, page: Int) async {
        // 标记搜索开始
        isSearchingFiles = true
        
        // 获取当前页范围
        let pageSize = 10
        let startIndex = page * pageSize
        
        // 检查缓存
        let cacheKey = NSString(string: "file_search_page_\(query)_\(page)")
        if let cachedResults = resultCache.object(forKey: cacheKey) as? [SearchResult] {
            // 将缓存的结果添加到现有结果中
            if !cachedResults.isEmpty {
                let allResults = fileResults + cachedResults
                // 更新结果，避免重复
                let uniqueResults = Array(Set(allResults))
                fileResults = uniqueResults.sorted(by: { $0.name < $1.name })
            }
            isSearchingFiles = false
            return
        }
        
        // 复用现有的文件搜索功能
        let newResults = await FileSearchService.searchFiles(query: query, startIndex: startIndex, limit: pageSize)
        
        // 缓存新结果
        resultCache.setObject(newResults as NSArray, forKey: cacheKey)
        
        // 将新结果添加到现有结果中
        if !newResults.isEmpty {
            let allResults = fileResults + newResults
            // 更新结果，避免重复
            let uniqueResults = Array(Set(allResults))
            fileResults = uniqueResults.sorted(by: { $0.name < $1.name })
        }
        
        // 标记搜索结束
        isSearchingFiles = false
    }
}
