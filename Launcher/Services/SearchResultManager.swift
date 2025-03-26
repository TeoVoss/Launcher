import Foundation
import AppKit
import Combine

class SearchResultManager: ObservableObject {
    // 发布结果
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var isSearching: Bool = false
    
    // 搜索服务
    private let appSearchService: ApplicationSearchService
    private let shortcutSearchService: ShortcutSearchService
    private let fileSearchService: FileSearchService
    
    // 用于取消订阅
    private var cancellables = Set<AnyCancellable>()
    
    // 用于保存当前的搜索任务
    private var currentSearchTask: Task<Void, Never>? = nil
    
    // 初始化所有搜索服务
    init() {
        self.appSearchService = ApplicationSearchService()
        self.shortcutSearchService = ShortcutSearchService()
        self.fileSearchService = FileSearchService()
        
        // 监听各服务的结果变化并更新总结果
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // 监听应用搜索结果
        appSearchService.$appResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
                print("- 应用: \(appSearchService.appResults.count)")
                self.updateResults()
            }
            .store(in: &cancellables)
        
        // 监听快捷指令搜索结果
        shortcutSearchService.$shortcutResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
                print("- 快捷指令: \(shortcutSearchService.shortcutResults.count)")
                self.updateResults()
            }
            .store(in: &cancellables)
        
        // 监听文件搜索结果
        fileSearchService.$fileResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
                print("- 文件: \(fileSearchService.fileResults.count)")
                self.updateResults()
            }
            .store(in: &cancellables)
    }
    
    // 执行搜索 - 使用并发方式
    func search(query: String) {
        // 取消之前的搜索任务
        currentSearchTask?.cancel()
        
        if query.isEmpty {
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
            
            // 等待所有搜索完成
            _ = await [systemAppsResults, shortcutsResults]
            
            await print("SRM 执行结果，应用 \(systemAppsResults.count)个结果")
            
            // 搜索完成后更新状态
            if !Task.isCancelled {
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }
    
    // 专门用于文件搜索的方法
    func searchFiles(query: String) {
        if query.isEmpty {
            clearFileResults()
            return
        }
        
        // 专门执行文件搜索
        Task { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run {
                self.fileSearchService.search(query: query)
            }
        }
    }
    
    // 清空文件搜索结果
    func clearFileResults() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.fileSearchService.clearResults()
        }
    }
    
    // 更新最终结果集 - 优化合并逻辑
    private func updateResults() {
        // 合并所有结果
        let allResults = combineResults()
        
        // 添加调试日志
        print("- 合并结果总数: \(allResults.count)")
        
        // 更新发布属性
        searchResults = allResults
        categories = categorizeResults(allResults)
        isSearching = false
    }
    
    // 优化结果合并过程，减少重复计算
    private func combineResults() -> [SearchResult] {
        var allResults = [SearchResult]()
        
        // 添加应用搜索结果
        allResults.append(contentsOf: appSearchService.appResults)
        
        // 添加快捷指令搜索结果
        allResults.append(contentsOf: shortcutSearchService.shortcutResults)
        
        // 添加文件搜索结果
        allResults.append(contentsOf: fileSearchService.fileResults)
        
        return allResults
    }
    
    // 根据类别组织结果
    private func categorizeResults(_ results: [SearchResult]) -> [SearchResultCategory] {
        let groupedResults = Dictionary(grouping: results) { $0.category }
        
        return groupedResults.map { (key, value) in
            SearchResultCategory(id: key, title: key, results: value)
        }.sorted { cat1, cat2 in
            // 自定义排序逻辑，确保重要类别在前面
            let order1 = getCategoryOrder(cat1.title)
            let order2 = getCategoryOrder(cat2.title)
            return order1 < order2
        }
    }
    
    // 获取类别的排序优先级
    private func getCategoryOrder(_ category: String) -> Int {
        switch category {
        case "应用程序": return 0
        case "系统设置": return 1
        case "快捷指令": return 2
        case "文档": return 3
        case "最近文件": return 4
        case "其他应用程序": return 5
        case "文件夹": return 6
        default: return 100
        }
    }
    
    // 清空搜索结果
    func clearResults() {
        Task { @MainActor in
            self.searchResults = []
            self.categories = []
            self.isSearching = false
            appSearchService.clearResults()
            shortcutSearchService.clearResults()
            fileSearchService.clearResults()
        }
    }
    
    // 打开搜索结果
    func openResult(_ result: SearchResult) {
        switch result.type {
        case .shortcut:
            // 使用快捷指令服务执行
            shortcutSearchService.runShortcut(result)
        default:
            // 默认使用NSWorkspace打开
            NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
        }
    }
} 
