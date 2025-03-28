import SwiftUI
import Combine

@MainActor
class MainViewModel: ObservableObject {
    // 各模块的数据
    @Published var modules: [ModuleSection] = []
    
    // 当前选中项的索引
    @Published var selectedItemIndex: SelectableItemIndex?
    
    // 搜索文本
    @Published var searchText: String = ""
    
    // 服务依赖
    private let searchService: SearchService
    let aiService: AIService
    
    // 各模块展开状态
    @Published var aiModuleExpanded: Bool = false
    @Published var fileModuleExpanded: Bool = false
    
    // 各模块加载状态
    @Published var isAILoading: Bool = false
    @Published var isFileSearchLoading: Bool = false
    
    // AI模块的prompt
    @Published var aiPrompt: String = ""
    
    // 文件搜索结果分页状态
    @Published var fileResultsPage: Int = 0
    
    // 缓存的搜索结果
    private var cachedApplicationResults: [SearchResult] = []
    private var _cachedFileResults: [SearchResult] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private var isUserSelected: Bool = false
    
    init(searchService: SearchService, aiService: AIService) {
        self.searchService = searchService
        self.aiService = aiService
        
        // 初始化模块数据
        self.modules = ModuleType.allCases.map { type in
            ModuleSection(type: type)
        }
        
        setupPublishers()
    }
    
    private func setupPublishers() {
        // 取消现有订阅
        cancellables.removeAll()
        
        // 监听搜索文本变更
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self = self else { return }
                self.updateSearchResults(for: text)
            }
            .store(in: &cancellables)
        
        // 监听搜索结果变化
        searchService.$searchResults
            .sink { [weak self] results in
                guard let self = self else { return }
                self.handleApplicationResultsUpdated(results)
            }
            .store(in: &cancellables)
        
        // 监听文件搜索结果变化
        searchService.$fileResults
            .sink { [weak self] results in
                guard let self = self else { return }
                self.handleFileResultsUpdated(results)
            }
            .store(in: &cancellables)
        
        // 设置AI响应监听器
        setupAIResponseListener()
    }
    
    // 更新所有模块展示数据
    func updateModules() {
        // 获取模块顺序的副本，确保我们使用的是引用类型
        var updatedModules = [ModuleSection]()
        
        // 决定哪些模块应该显示
        let shouldShowAI = shouldShowAIModule
        let shouldShowApplications = !cachedApplicationResults.isEmpty
        let shouldShowFiles = !searchText.isEmpty
        let shouldShowCalculator = searchService.searchResults.contains { $0.type == .calculator }
        
        // 只添加需要显示的模块
        
        // 计算器模块应该在最前面显示
        if shouldShowCalculator {
            let calculatorItems = searchService.searchResults.filter { $0.type == .calculator }.map { result -> CalculatorItem in
                return CalculatorItem(
                    formula: result.formula ?? result.name,
                    result: result.calculationResult ?? result.subtitle
                )
            }
            
            if !calculatorItems.isEmpty {
                updatedModules.append(ModuleSection(
                    type: .calculator,
                    items: calculatorItems
                ))
            }
        }
        
        if shouldShowAI {
            var aiItems: [any SelectableItem] = [AIQueryItem(query: searchText)]
            
            // 如果AI模块展开，添加AI回复项
            if aiModuleExpanded {
                // 获取AI响应内容
                let responseContent = aiService.response
                if !responseContent.isEmpty || isAILoading {
                    // 添加AI回复项
                    aiItems.append(AIResponseItem(content: responseContent))
                }
            }
            
            updatedModules.append(ModuleSection(
                type: .ai,
                items: aiItems,
                isExpanded: aiModuleExpanded,
                isLoading: isAILoading
            ))
        }
        
        if shouldShowApplications {
            let appItems: [any SelectableItem] = cachedApplicationResults.map { $0.toSelectableItem() }
            updatedModules.append(ModuleSection(
                type: .application,
                items: appItems
            ))
        }
        
        if shouldShowFiles {
            var fileItems: [any SelectableItem] = [FileSearchItem(query: searchText)]
            
            // 如果文件搜索模块展开，添加文件结果
            if fileModuleExpanded && !_cachedFileResults.isEmpty {
                let fileResultItems: [any SelectableItem] = _cachedFileResults.map { $0.toSelectableItem() }
                fileItems.append(contentsOf: fileResultItems)
            }
            
            updatedModules.append(ModuleSection(
                type: .file,
                items: fileItems,
                isExpanded: fileModuleExpanded,
                isLoading: isFileSearchLoading
            ))
        }
        
        // 更新模块列表
        self.modules = updatedModules
        
        // 如果当前选中的模块不再存在，或者项索引超出范围，重置选择
        validateSelectedIndex()
    }
    
    // 验证当前选中的索引是否有效
    private func validateSelectedIndex() {
        if modules.isEmpty {
            isUserSelected = false
            return
        }
            
        let firstModule = modules.first!
        let newIndex = SelectableItemIndex(
            moduleType: firstModule.type,
            itemIndex: 0,
            isHeader: firstModule.type == .ai || firstModule.type == .file
        )
        guard let selectedItemIndex = selectedItemIndex else {
            self.selectedItemIndex = newIndex
            isUserSelected = false
            return
        }
        if !isUserSelected {
            self.selectedItemIndex = newIndex
            print("选中的模块: \(firstModule.type)\(self.selectedItemIndex)")
            return
        }
        // 查找所选模块
        if let moduleIndex = modules.firstIndex(where: { $0.type == selectedItemIndex.moduleType }) {
            let module = modules[moduleIndex]
            
            // 检查项索引是否有效
            if selectedItemIndex.itemIndex >= module.items.count {
                // 索引超出范围，重置为nil
                self.selectedItemIndex = newIndex
                isUserSelected = false
            }
        } else {
            // 所选模块不存在，重置为nil
            self.selectedItemIndex = newIndex
            isUserSelected = false
        }
        print("选中的模块: \(firstModule.type)\(self.selectedItemIndex)")
    }
    
    // 切换模块的展开/折叠状态
    func toggleModule(_ moduleType: ModuleType) {
        switch moduleType {
        case .ai:
            toggleAIModule()
        case .file:
            toggleFileModule()
        default:
            break
        }
    }
    
    // 切换AI模块展开状态
    func toggleAIModule() {
        if !aiModuleExpanded && !searchText.isEmpty {
            // 首次展开，保存当前查询
            aiPrompt = searchText
            sendAIRequest()
        }
        
        withAnimation {
            aiModuleExpanded.toggle()
            
            if !aiModuleExpanded {
                // 折叠时取消请求
                aiService.cancelRequests()
                isAILoading = false
            }
        }
        
        // 更新模块数据
        updateModules()
    }
    
    // 切换文件模块展开状态
    func toggleFileModule() {
        // 先设置展开状态
        fileModuleExpanded.toggle()
        
        if fileModuleExpanded {
            // 展开文件搜索时，开始执行搜索
            isFileSearchLoading = true
            Task {
                // 确保文件搜索结果被加载并显示
                await MainActor.run {
                    searchService.searchFiles(query: searchText)
                }
                
            }
        }
        
        // 更新模块数据
        updateModules()
    }
    
    // 发送AI请求
    func sendAIRequest() {
        guard !aiPrompt.isEmpty else { return }
        
        isAILoading = true
        
        Task {
            await aiService.sendRequest(prompt: aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
            await MainActor.run {
                isAILoading = false
            }
        }
    }
    
    // 加载更多文件结果
    func loadMoreFileResults() {
        fileResultsPage += 1
        isFileSearchLoading = true
        Task {
            await searchService.searchMoreFiles(query: searchText, page: fileResultsPage)
        }
    }
    
    // 处理可选择项的点击
    func handleItemSelection(_ index: SelectableItemIndex) {
        self.selectedItemIndex = index
        
        // 根据模块类型执行相应的操作
        switch index.moduleType {
        case .ai:
            if index.isHeader {
                toggleAIModule()
            } else if aiModuleExpanded {
                // 如果是AI回复项（索引为1）
                if index.itemIndex == 1 {
                    // 暂时只记录点击，未来可以扩展功能，如复制或展开详细对话窗口
                    print("点击了AI回复项")
                    // TODO: 处理AI回复项的点击动作
                }
            }
            
        case .application:
            // 获取应用模块
            if let appModule = modules.first(where: { $0.type == .application }) {
                // 确保索引有效
                if index.itemIndex < appModule.items.count {
                    // 获取应用项
                    let item = appModule.items[index.itemIndex]
                    if let appItem = item as? ApplicationItem {
                        // 执行应用项的点击
                        searchService.executeResult(appItem.searchResult)
                    }
                }
            }
            
        case .file:
            if index.isHeader {
                toggleFileModule()
            } else {
                // 获取文件模块
                if let fileModule = modules.first(where: { $0.type == .file }) {
                    // 确保索引有效（需要减去1，因为第一项是头部）
                    let fileIndex = index.itemIndex - 1
                    if fileIndex >= 0 && fileIndex < _cachedFileResults.count {
                        // 执行文件项的点击
                        searchService.executeResult(_cachedFileResults[fileIndex])
                    }
                }
            }
            
        case .calculator:
            // 获取计算器模块
            if let calcModule = modules.first(where: { $0.type == .calculator }) {
                // 确保索引有效
                if index.itemIndex < calcModule.items.count {
                    // 获取计算器项
                    let item = calcModule.items[index.itemIndex]
                    if let calcItem = item as? CalculatorItem {
                        // 复制计算结果到剪贴板
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(calcItem.result, forType: .string)
                        
                        // 提供反馈
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    }
                }
            }
            
        default:
            break
        }
    }
    
    // 处理键盘导航
    func handleKeyboardNavigation(_ direction: NavigationDirection) {
        switch direction {
        case .up:
            navigateUp()
        case .down:
            navigateDown()
        case .enter:
            handleEnterKey()
        case .escape:
            handleEscapeKey()
        }
    }
    
    // 导航上键
    private func navigateUp() {
        guard !modules.isEmpty else { return }
        
        isUserSelected = true
        
        if let currentIndex = selectedItemIndex {
            // 当前有选择的项
            let currentModuleType = currentIndex.moduleType
            let currentItemIndex = currentIndex.itemIndex
            
            // 查找当前模块的索引
            if let moduleIndex = modules.firstIndex(where: { $0.type == currentModuleType }) {
                if currentItemIndex > 0 {
                    // 在当前模块内向上移动
                    selectedItemIndex = SelectableItemIndex(
                        moduleType: currentModuleType,
                        itemIndex: currentItemIndex - 1,
                        isHeader: currentItemIndex - 1 == 0 && (currentModuleType == .ai || currentModuleType == .file)
                    )
                } else if moduleIndex > 0 {
                    // 移动到上一个模块的最后一项
                    let prevModule = modules[moduleIndex - 1]
                    let lastItemIndex = prevModule.items.count - 1
                    selectedItemIndex = SelectableItemIndex(
                        moduleType: prevModule.type,
                        itemIndex: lastItemIndex,
                        isHeader: lastItemIndex == 0 && (prevModule.type == .ai || prevModule.type == .file)
                    )
                }
            }
        } else {
            // 当前没有选择项，选择最后一个模块的最后一项
            let lastModule = modules.last!
            let lastItemIndex = lastModule.items.count - 1
            selectedItemIndex = SelectableItemIndex(
                moduleType: lastModule.type,
                itemIndex: lastItemIndex,
                isHeader: lastItemIndex == 0 && (lastModule.type == .ai || lastModule.type == .file)
            )
        }
    }
    
    // 导航下键
    private func navigateDown() {
        guard !modules.isEmpty else { return }
        
        isUserSelected = true
        
        if let currentIndex = selectedItemIndex {
            // 当前有选择的项
            let currentModuleType = currentIndex.moduleType
            let currentItemIndex = currentIndex.itemIndex
            
            // 查找当前模块的索引
            if let moduleIndex = modules.firstIndex(where: { $0.type == currentModuleType }) {
                let currentModule = modules[moduleIndex]
                
                if currentItemIndex < currentModule.items.count - 1 {
                    // 在当前模块内向下移动
                    selectedItemIndex = SelectableItemIndex(
                        moduleType: currentModuleType,
                        itemIndex: currentItemIndex + 1,
                        isHeader: false
                    )
                } else if moduleIndex < modules.count - 1 {
                    // 移动到下一个模块的第一项
                    let nextModule = modules[moduleIndex + 1]
                    selectedItemIndex = SelectableItemIndex(
                        moduleType: nextModule.type,
                        itemIndex: 0,
                        isHeader: nextModule.type == .ai || nextModule.type == .file
                    )
                }
            }
        } else {
            // 当前没有选择项，选择第一个模块的第一项
            let firstModule = modules.first!
            selectedItemIndex = SelectableItemIndex(
                moduleType: firstModule.type,
                itemIndex: 0,
                isHeader: firstModule.type == .ai || firstModule.type == .file
            )
        }
    }
    
    // 处理回车键
    private func handleEnterKey() {
        if let selectedIndex = selectedItemIndex {
            handleItemSelection(selectedIndex)
        } else if !modules.isEmpty {
            // 如果没有选中项但有模块，选中第一个模块的第一项
            let firstModule = modules.first!
            let newIndex = SelectableItemIndex(
                moduleType: firstModule.type,
                itemIndex: 0,
                isHeader: firstModule.type == .ai || firstModule.type == .file
            )
            selectedItemIndex = newIndex
            handleItemSelection(newIndex)
        }
    }
    
    // 处理ESC键
    private func handleEscapeKey() {
        if aiModuleExpanded || fileModuleExpanded {
            // 如果有展开的模块，先关闭
            if aiModuleExpanded {
                aiModuleExpanded = false
            }
            if fileModuleExpanded {
                fileModuleExpanded = false
            }
            selectedItemIndex = nil
            updateModules()
        } else if !searchText.isEmpty {
            // 如果搜索文本非空，清空搜索
            searchText = ""
            selectedItemIndex = nil
        } else {
            // 退出应用
            NSApp.hide(nil)
        }
    }
    
    // 更新搜索结果
    private func updateSearchResults(for text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 空搜索直接清理
        if trimmedText.isEmpty {
            resetSearch()
            return
        }
        
        // 执行搜索
        Task { @MainActor in
            searchService.search(query: trimmedText)
            
            // 如果文件模块已展开，执行文件搜索
            if fileModuleExpanded {
                isFileSearchLoading = true
                searchService.searchFiles(query: trimmedText)
            }
        }
    }
    
    // 处理应用搜索结果更新
    private func handleApplicationResultsUpdated(_ results: [SearchResult]) {
        // 过滤只保留应用类型的结果
        let appResults = results.filter { $0.type == .application || $0.type == .shortcut }
        cachedApplicationResults = appResults
        
        // 更新模块数据
        updateModules()
    }
    
    // 处理文件搜索结果更新
    private func handleFileResultsUpdated(_ results: [SearchResult]) {
        _cachedFileResults = results
        // 明确停止加载状态
        isFileSearchLoading = false
        // 更新模块数据
        updateModules()
        
        // 打印日志确认结果
        print("文件搜索结果已更新: \(results.count)个结果，文件搜索模块展开状态: \(fileModuleExpanded)")
    }
    
    // 重置搜索状态
    func resetSearch() {
        // 重置所有状态
        cachedApplicationResults = []
        _cachedFileResults = []
        aiModuleExpanded = false
        fileModuleExpanded = false
        selectedItemIndex = nil
        searchService.clearResults()
        
        // 更新模块数据
        updateModules()
    }
    
    // 清空搜索文本
    func clearSearchText() {
        searchText = ""
    }
    
    // 判断是否应该显示AI模块
    var shouldShowAIModule: Bool {
        return searchText.count >= 3
    }
    
    // 监听AI响应变化以更新模块
    func setupAIResponseListener() {
        // 监听AI响应变化
        aiService.$response
            .sink { [weak self] _ in
                // AI响应发生变化时更新模块数据
                guard let self = self else { return }
                if self.aiModuleExpanded {
                    self.updateModules()
                }
            }
            .store(in: &cancellables)
    }
}

// 键盘导航方向
enum NavigationDirection {
    case up
    case down
    case enter
    case escape
} 
