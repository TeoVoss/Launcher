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
                self.updateResults()
            }
            .store(in: &cancellables)
        
        // 监听快捷指令搜索结果
        shortcutSearchService.$shortcutResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
                self.updateResults()
            }
            .store(in: &cancellables)
        
        // 监听文件搜索结果
        fileSearchService.$fileResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
                self.updateResults()
            }
            .store(in: &cancellables)
    }
    
    // 执行搜索
    func search(query: String) {
        // 清空之前的结果
        if query.isEmpty {
            clearResults()
            return
        }
        
        isSearching = true
        
        // 并行执行不同类型的搜索
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 搜索系统应用
            _ = self.appSearchService.search(query: query, systemAppsOnly: true)
            
            // 搜索快捷指令
            _ = self.shortcutSearchService.search(query: query)
            
            // 不再默认搜索文件，改为仅在用户选择文件搜索入口时才搜索
            // self.fileSearchService.search(query: query)
        }
    }
    
    // 专门用于文件搜索的方法
    func searchFiles(query: String) {
        if query.isEmpty {
            clearFileResults()
            return
        }
        
        // 专门执行文件搜索
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fileSearchService.search(query: query)
        }
    }
    
    // 清空文件搜索结果
    func clearFileResults() {
        DispatchQueue.main.async {
            self.fileSearchService.fileResults = []
            // 确保更新结果集，避免残留
            self.updateResults()
        }
    }
    
    // 更新最终结果集
    private func updateResults() {
        // 合并所有结果
        let allResults = appSearchService.appResults + 
                         shortcutSearchService.shortcutResults + 
                         fileSearchService.fileResults
        
        // 更新发布属性
        searchResults = allResults
        categories = categorizeResults(allResults)
        isSearching = false
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
        DispatchQueue.main.async {
            self.searchResults = []
            self.categories = []
            self.isSearching = false
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