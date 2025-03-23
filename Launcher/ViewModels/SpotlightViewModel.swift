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
    
    // 标记搜索中状态，但不影响高度计算
    private(set) var isSearching = false
    
    // 缓存的显示结果，避免重复计算
    private var _cachedDisplayResults: [SearchResult] = []
    // 记录上次结果数量，用于判断是否需要更新高度
    private var lastResultCount: Int = 0
    
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
    
    // displayResults简化为直接返回缓存结果
    var displayResults: [SearchResult] {
        return _cachedDisplayResults
    }
    
    init(searchService: SearchService, aiService: AIService) {
        self.searchService = searchService
        self.aiService = aiService
        
        // 初始化并配置发布者
        setupPublishers()
    }
    
    // 单一集中的发布者设置 - 避免重复订阅
    private func setupPublishers() {
        // 取消任何现有订阅
        cancellables.removeAll()
        
        // 搜索文本变更发布者 - 使用更可靠的去重机制
        $searchText
            .dropFirst()  // 忽略初始值
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)  // 增加防抖时间
            .removeDuplicates()  // 防止重复触发相同搜索
            .filter { text in
                // 避免重复处理相同查询
                let lastQuery = UserDefaults.standard.string(forKey: "LastSearchQuery") ?? ""
                let isDifferent = text.trimmingCharacters(in: .whitespacesAndNewlines) != 
                                 lastQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                return isDifferent
            }
            .sink { [weak self] text in
                guard let self = self else { return }
                
                // 记录本次搜索
                UserDefaults.standard.set(text, forKey: "LastSearchQuery")
                
                // 更新搜索结果 - 使用更新过的方法
                self.updateSearchResults(for: text)
            }
            .store(in: &cancellables)
        
        // 监听搜索服务结果变化 - 添加更强的过滤和去重
        searchService.$searchResults
            .filter { [weak self] results in
                // 只在普通搜索模式下更新
                guard let self = self, 
                      !self.showingFileSearch && !self.showingAIResponse else {
                    return false
                }
                
                // 避免重复更新相同结果
                if results.count == self.lastResultCount && !self._cachedDisplayResults.isEmpty {
                    let newSignature = results.map { $0.id.uuidString }.joined()
                    let oldSignature = self._cachedDisplayResults
                        .filter { $0.type != .ai && $0.type != .file }
                        .map { $0.id.uuidString }
                        .joined()
                    
                    // 使用ID组合作为签名，快速比较结果集是否相同
                    return newSignature != oldSignature
                }
                
                return true
            }
            .sink { [weak self] results in
                guard let self = self else { return }
                // 搜索结果更新时，更新缓存并计算高度
                self.handleSearchResultsUpdated(results)
            }
            .store(in: &cancellables)
        
        // 监听文件搜索结果变化
        searchService.$fileSearchResults
            .filter { [weak self] _ in
                // 仅在文件搜索模式下更新
                return self?.showingFileSearch == true
            }
            .removeDuplicates { prev, next in
                // 比较结果是否实质相同
                prev.count == next.count
            }
            .sink { [weak self] results in
                guard let self = self else { return }
                print("【搜索结果】文件搜索完成，获得\(results.count)个结果")
                self.updateFileSearchResultsHeight(results)
            }
            .store(in: &cancellables)
            
        // 监听视图模式变化
        Publishers.CombineLatest($showingAIResponse, $showingFileSearch)
            .removeDuplicates { prev, next in
                prev.0 == next.0 && prev.1 == next.1
            }
            .sink { [weak self] (showingAI, showingFile) in
                guard let self = self else { return }
                print("模式变化: AI=\(showingAI), 文件=\(showingFile)")
                
                let viewMode: ViewMode
                if showingAI {
                    viewMode = .aiResponse
                } else if showingFile {
                    viewMode = .fileSearch
                } else {
                    viewMode = .search
                }
                
                // 模式切换使用一次性操作，避免循环
                self.handleModeChange(to: viewMode)
            }
            .store(in: &cancellables)
    }
    
    // 处理模式变化的统一函数 - 避免重复代码
    private func handleModeChange(to mode: ViewMode) {
        switch mode {
        case .aiResponse:
            // AI视图模式
            WindowCoordinator.shared.handleModeTransition(
                to: .aiResponse,
                customHeight: LauncherSize.Fixed.searchBarHeight + LauncherSize.Fixed.minAIContentHeight
            )
        case .fileSearch:
            // 文件搜索模式 - 先使用最小高度，后续会根据结果数量更新
            WindowCoordinator.shared.handleModeTransition(
                to: .fileSearch,
                customHeight: LauncherSize.Fixed.searchBarHeight + LauncherSize.Fixed.minFileSearchHeight
            )
        case .search:
            // 常规搜索模式 - 直接启动结果计算，只有当前无结果时才重新搜索
            if _cachedDisplayResults.isEmpty && !searchText.isEmpty {
                self.updateSearchResults(for: self.searchText)
            } else {
                // 已有结果则直接更新窗口高度
                self.updateSearchResultsHeight()
            }
        }
    }
    
    // 更新搜索结果 - 添加更智能的处理逻辑
    func updateSearchResults(for text: String) {
        // 标记搜索开始
        isSearching = true
        
        // 保存搜索文本 - 使用单一键
        UserDefaults.standard.set(text, forKey: "LastSearchText")
        
        // 生成本次搜索的唯一标识
        let searchID = UUID().uuidString
        let currentSearchID = searchID
        
        // 空搜索直接处理 - 使用批量处理
        if text.isEmpty {
            // 创建处理队列，批量应用所有更改
            DispatchQueue.main.async { [self] in
                // 1. 重置所有缓存
                self._cachedDisplayResults = []
                self.lastResultCount = 0
                self.isSearching = false
                self.selectedIndex = nil
                
                // 2. 更新高度状态
                self.contentHeight = 0
                self.height = 60
                
                // 3. 延迟重置窗口高度，确保UI状态稳定
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    WindowCoordinator.shared.resetWindowHeight()
                }
            }
            return
        }
        
        // 正常搜索处理 - 使用任务方式
        Task { @MainActor in
            // 防止竞争条件
            if currentSearchID != searchID { return }
            
            // 执行搜索并等待结果
            searchService.search(query: text)
        }
    }
    
    // 构建特殊入口，统一处理逻辑，避免重复代码
    private func buildSpecialEntries(_ text: String) -> [SearchResult] {
        var entries: [SearchResult] = []
        
        // 只在输入长度满足要求时才显示AI入口
        if text.count >= 3 {
            let aiResult = SearchResult(
                id: UUID(),
                name: "Ask AI: \(text)",
                path: "",
                type: .ai,
                category: "AI",
                icon: NSImage(systemSymbolName: "brain.fill", accessibilityDescription: nil) ?? NSImage(),
                subtitle: "使用 AI 回答问题"
            )
            entries.append(aiResult)
        }
        
        return entries
    }
    
    // 构建文件搜索入口
    private func buildFileSearchEntry(_ text: String) -> SearchResult? {
        // 文本为空时不显示文件搜索入口
        if text.isEmpty {
            return nil
        }
        
        return SearchResult(
            id: UUID(),
            name: "搜索文件: \(text)",
            path: "",
            type: .file,
            category: "文件搜索",
            icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
            subtitle: "搜索本地文件"
        )
    }
    
    // 处理搜索结果更新 - 避免不必要的状态变化
    private func handleSearchResultsUpdated(_ results: [SearchResult]) {
        // 搜索完成，清除搜索中状态
        isSearching = false
        
        // 如果不在普通搜索模式，忽略结果
        if showingAIResponse || showingFileSearch {
            return
        }
        
        // 创建标准化的结果集 - 批量构建
        var entries: [SearchResult] = []
        
        // 添加特殊入口（AI、文件搜索等）
        let aiEntries = buildSpecialEntries(searchText)
        if !aiEntries.isEmpty {
            entries.append(contentsOf: aiEntries)
        }
        
        // 添加应用搜索结果
        if !results.isEmpty {
            entries.append(contentsOf: results)
        }
        
        // 添加文件搜索入口
        if let fileEntry = buildFileSearchEntry(searchText) {
            entries.append(fileEntry)
        }
        
        // 如果结果相同，跳过更新
        if entries.count == _cachedDisplayResults.count {
            let newIds = entries.map { $0.id.uuidString }.joined()
            let oldIds = _cachedDisplayResults.map { $0.id.uuidString }.joined()
            if newIds == oldIds {
                return
            }
        }
        
        // 批量更新视图状态
        DispatchQueue.main.async { [self] in
            // 更新缓存
            self._cachedDisplayResults = entries
            self.lastResultCount = entries.count
            
            // 更新高度
            self.updateSearchResultsHeight()
            
            // 确保有结果时选中第一项
            if !entries.isEmpty && self.selectedIndex == nil {
                self.selectedIndex = 0
            }
        }
    }
    
    // 更新普通搜索结果高度
    private func updateSearchResultsHeight() {
        let results = displayResults
        print("更新搜索结果高度: 结果数 \(results.count)")
        
        // 当无结果时使用最小高度
        if results.isEmpty && !searchText.isEmpty {
            // 设置为基础高度，不显示内容区域
            let newHeight = LauncherSize.Fixed.searchBarHeight
            
            // 更新本地高度状态
            self.contentHeight = 0
            self.height = newHeight
            
            // 通过协调器更新窗口
            WindowCoordinator.shared.updateWindowHeight(to: newHeight)
            return
        }
        
        // 计算窗口高度
        let newHeight = LauncherSize.getHeightForMode(.search, itemCount: results.count)
        
        // 更新本地高度状态
        self.contentHeight = newHeight - LauncherSize.Fixed.searchBarHeight
        self.height = newHeight
        
        // 通过协调器更新窗口
        WindowCoordinator.shared.updateWindowHeight(to: newHeight)
    }
    
    // 更新文件搜索结果高度
    private func updateFileSearchResultsHeight(_ results: [SearchResult]) {
        print("更新文件搜索高度: 结果数 \(results.count)")
        
        // 计算窗口高度
        let newHeight = LauncherSize.getHeightForMode(.fileSearch, itemCount: results.count)
        
        // 更新本地高度状态
        self.contentHeight = newHeight - LauncherSize.Fixed.searchBarHeight
        self.height = newHeight
        
        // 通过协调器更新窗口
        WindowCoordinator.shared.updateWindowHeight(to: newHeight)
    }
    
    // 直接更新高度
    func updateContentHeight(_ newContentHeight: CGFloat) {
        let mode = self.currentMode
        
        // 计算窗口高度
        let totalHeight = LauncherSize.getHeightForCustomContent(newContentHeight, mode: mode)
        
        // 更新高度状态
        self.contentHeight = newContentHeight
        self.height = totalHeight
        
        // 立即调整窗口高度
        WindowCoordinator.shared.updateWindowHeight(to: totalHeight)
    }
    
    func performSearch(text: String) {
        // 使用统一的搜索结果管理方法
        updateSearchResults(for: text)
    }
    
    func handleItemClick(_ result: SearchResult) {
        switch result.type {
        case .ai:
            // 设置状态
            prompt = searchText
            showingAIResponse = true
            selectedIndex = nil
            
            // AI请求将在视图加载时自动启动
            
        case .file:
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
        
        // 使用两阶段清理，先清除文本，再调整窗口大小
        // 阶段一：清除UI状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 先保存当前高度
            let oldHeight = self.height
            
            // 重置搜索状态 - 但推迟高度调整
            self.searchText = ""
            self.selectedIndex = nil
            self.showingAIResponse = false
            self.showingFileSearch = false
            
            // 重置本地高度状态
            self.contentHeight = 0
            self.height = 60
            
            // 阶段二：延迟调整窗口大小
            let delay = oldHeight > 200 ? 0.15 : 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // 调整窗口大小 - 使用协调器，确保动画平滑
                WindowCoordinator.shared.resetWindowHeight()
            }
        }
    }
    
    func requestFocus() {
        // 通过NotificationCenter发送请求焦点通知
        NotificationCenter.default.post(name: Notification.Name("RequestSearchFocus"), object: nil)
    }
    
    // 从AI或文件搜索视图返回 - 使用协调器
    func exitCurrentMode() {
        print("退出当前模式: \(currentMode)")
        
        // 记住当前搜索文本
        let currentText = searchText
        
        // 退出文件搜索模式到普通搜索模式的特殊处理
        let wasInFileSearch = showingFileSearch
        
        // 清空所有状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 清空视图状态标志
            self.showingAIResponse = false
            self.showingFileSearch = false
            self.selectedIndex = nil
            
            // 2. 重置高度 - 使用协调器，避免闪烁
            self.contentHeight = 0
            self.height = LauncherSize.Fixed.searchBarHeight
            WindowCoordinator.shared.handleModeTransition(to: .search)
            
            // 3. 彻底清空搜索服务中的结果
            if wasInFileSearch {
                // 从文件搜索返回时，确保文件搜索结果被完全清空
                self.searchService.clearAllResults()
                
                // 延迟一点再重新执行搜索，确保状态完全重置
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.performSearch(text: currentText)
                }
            } else {
                // 从AI对话返回时可以直接执行搜索
                self.performSearch(text: currentText)
            }
        }
    }
} 