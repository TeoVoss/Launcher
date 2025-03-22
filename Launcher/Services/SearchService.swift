import Foundation
import AppKit
import Combine

// 搜索服务 - 对外提供统一接口，内部委托给专门的搜索服务
class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var fileSearchResults: [SearchResult] = []
    
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
            }
            searchResultManager.clearFileResults()
            return
        }
        
        // 专门执行文件搜索
        searchResultManager.searchFiles(query: query)
    }
    
    // 保持与原有API兼容的打开结果方法
    func openResult(_ result: SearchResult) {
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
} 