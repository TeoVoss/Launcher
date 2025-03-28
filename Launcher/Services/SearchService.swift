import Foundation
import AppKit
import Combine

// 搜索服务 - 对外提供统一接口，内部委托给专门的搜索服务
class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var fileResults: [SearchResult] = []
    @Published var isSearchingFiles: Bool = false
    @Published var isSearching: Bool = false
    
    // 搜索服务
    private let appSearchService: ApplicationSearchService
    private let shortcutSearchService: ShortcutSearchService
    private let fileSearchService: FileSearchService
    
    private var cancellables = Set<AnyCancellable>()
    
    // 搜索结果缓存 - 提高频繁搜索同一内容的性能
    private var resultCache = NSCache<NSString, NSArray>()
    
    // 当前正在执行的搜索任务
    private var currentSearchTask: Task<Void, Never>? = nil
    private var currentFileSearchTask: Task<Void, Never>? = nil
    
    init() {
        // 初始化搜索结果管理器
        self.appSearchService = ApplicationSearchService()
        self.shortcutSearchService = ShortcutSearchService()
        self.fileSearchService = FileSearchService()
        
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
        // 监听应用搜索结果
        appSearchService.$appResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
                print("- 应用: \(appSearchService.appResults.count)")
                self.updateSearchResults()
            }
            .store(in: &cancellables)
        
        // 监听快捷指令搜索结果
        shortcutSearchService.$shortcutResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
                print("- 快捷指令: \(shortcutSearchService.shortcutResults.count)")
                self.updateSearchResults()
            }
            .store(in: &cancellables)
        
        fileSearchService.$fileResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                self?.fileResults = results
            }
            .store(in: &cancellables)
    }
    
    private func updateSearchResults() {
        // 合并所有结果
        let allResults = combineResults()
        
        // 添加调试日志
        print("- 合并结果总数: \(allResults.count)")
        
        // 更新发布属性
        searchResults = allResults
    }
    
    private func combineResults() -> [SearchResult] {
        var allResults = [SearchResult]()
        
        // 添加应用搜索结果
        allResults.append(contentsOf: appSearchService.appResults)
        
        // 添加快捷指令搜索结果
        allResults.append(contentsOf: shortcutSearchService.shortcutResults)
        
        return allResults
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
        
        isSearching = true
        
        // 创建新的并发搜索任务
        currentSearchTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 标记搜索开始
            await MainActor.run {
                self.isSearching = true
            }
            
            // 检查是否取消
            if Task.isCancelled { return }
            
            // 并发执行不同类型的搜索
            async let systemAppsResults = self.appSearchService.search(query: query)
            async let shortcutsResults = self.shortcutSearchService.search(query: query)
            
            // 等待搜索完成
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            // 如果任务没有被取消，缓存结果
            if !Task.isCancelled {
                await MainActor.run {
                    // 缓存结果
                    self.resultCache.setObject(self.searchResults as NSArray, forKey: cacheKey)
                    self.isSearching = false
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
            clearFileResults()
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
        
        self.isSearchingFiles = true
        
        // 创建新的文件搜索任务
        currentFileSearchTask = Task { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run {
                self.fileSearchService.search(query: query)
            }
            
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
        switch result.type {
        case .shortcut:
            // 使用快捷指令服务执行
            shortcutSearchService.runShortcut(result)
        default:
            // 默认使用NSWorkspace打开
            NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
        }
    }
    
    // 清空文件搜索结果
    func clearFileResults() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.fileSearchService.clearResults()
        }
    }
    
    // 清空搜索结果
    func clearResults() {
        currentSearchTask?.cancel()
        currentFileSearchTask?.cancel()
        Task { @MainActor in
            self.searchResults = []
            self.categories = []
            self.isSearching = false
            appSearchService.clearResults()
            shortcutSearchService.clearResults()
            fileSearchService.clearResults()
        }
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
