import Foundation
import AppKit
import Combine

// 搜索服务 - 对外提供统一接口，内部委托给专门的搜索服务
class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var fileResults: [SearchResult] = []
    @Published var isSearchingFiles: Bool = false
    
    // 搜索服务
    private let appSearchService: ApplicationSearchService
    private let shortcutSearchService: ShortcutSearchService
    private let fileSearchService: FileSearchService
    private let calculatorService: CalculatorService
    
    private var cancellables = Set<AnyCancellable>()
    
    // 当前正在执行的搜索任务
    private var currentSearchTask: Task<Void, Never>? = nil
    private var currentFileSearchTask: Task<Void, Never>? = nil
    
    init() {
        // 初始化搜索结果管理器
        self.appSearchService = ApplicationSearchService()
        self.shortcutSearchService = ShortcutSearchService()
        self.fileSearchService = FileSearchService()
        self.calculatorService = CalculatorService()
        
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
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
//                print("- 应用: \(appSearchService.appResults.count)")
                self.updateSearchResults()
            }
            .store(in: &cancellables)
        
        // 监听快捷指令搜索结果
        shortcutSearchService.$shortcutResults
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
//                print("- 快捷指令: \(shortcutSearchService.shortcutResults.count)")
                self.updateSearchResults()
            }
            .store(in: &cancellables)
        
        fileSearchService.$fileResults
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self = self else { return }
                self.fileResults = results
                self.isSearchingFiles = fileSearchService.isSearchingFile
//                print("- 文件: \(fileSearchService.fileResults.count)")
            }
            .store(in: &cancellables)
        
        calculatorService.$calculatorResult
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                guard let self = self else { return }
                print("calculatorResult Change")
                self.updateSearchResults()
            }
            .store(in: &cancellables)
    }
    
    private func updateSearchResults() {
        // 合并所有结果
        let allResults = combineResults()
        
        // 添加调试日志
//        print("- 合并结果总数: \(allResults.count)")
        
        // 更新发布属性
        searchResults = allResults
    }
    
    private func combineResults() -> [SearchResult] {
        var allResults = [SearchResult]()
        
        if !self.calculatorService.calculatorResult.isEmpty {
            // 计算器结果优先显示
            allResults.append(contentsOf: calculatorService.calculatorResult)
        }
        
        // 添加应用搜索结果
        allResults.append(contentsOf: appSearchService.appResults)
        
        // 添加快捷指令搜索结果
        allResults.append(contentsOf: shortcutSearchService.shortcutResults)
        
        return allResults
    }
    
    func search(query: String) {
        // 取消之前的搜索任务
        currentSearchTask?.cancel()
        
        // 如果查询为空，则直接清除结果
        if query.isEmpty {
            return
        }
        
        self.calculatorService.calculate(query)
        
        // 创建新的并发搜索任务
        currentSearchTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 检查是否取消
            if Task.isCancelled { return }
            
            // 并发执行不同类型的搜索
            async let _ = self.appSearchService.search(query: query)
            async let _ = self.shortcutSearchService.search(query: query)
        }
    }
    
    // 保持与原有API兼容的文件搜索方法 - 添加缓存和并发支持
    func searchFiles(query: String) {
        // 取消之前的文件搜索任务
        currentFileSearchTask?.cancel()
        
        // 如果查询为空，则直接清除文件搜索结果
        if query.isEmpty {
            clearFileResults()
            return
        }
        
        // 创建新的文件搜索任务
        currentFileSearchTask = Task { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run {
                self.fileSearchService.search(query: query)
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
            self.fileResults = []
        }
    }
    
    // 清空搜索结果
    func clearResults() {
        currentSearchTask?.cancel()
        currentFileSearchTask?.cancel()
        Task { @MainActor in
            self.searchResults = []
            self.categories = []
        }
    }
    
    // 添加分页搜索文件的方法 - 保持原有功能
    @MainActor
    func searchMoreFiles(query: String, page: Int) async {
        // 标记搜索开始
//        isSearchingFiles = true
        
        // 加载更多
        await MainActor.run {
            self.fileSearchService.search(query: query, loadMore: true)
        }
    }
}
