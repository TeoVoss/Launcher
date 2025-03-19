import SwiftUI
import AppKit

// 搜索栏组件
struct SearchBar: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool
    var onClear: () -> Void
    
    var body: some View {
        ZStack {
            DraggableView()
            
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24))
                    .focused($isFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }
                
                if !searchText.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 60)  // 固定搜索框高度
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .opacity(0.8)
        )
    }
}

// 添加拖动功能的 NSView
struct DraggableView: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        let view = DraggableNSView()
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

// 自定义 NSView 子类来处理拖动
class DraggableNSView: NSView {
    private var isDragging = false
    private var initialMouseLocation: NSPoint?
    private var initialWindowLocation: NSPoint?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowLocation = window.frame.origin
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = window,
              let initialMouseLocation = initialMouseLocation,
              let initialWindowLocation = initialWindowLocation else { return }
        
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y
        
        let newOrigin = NSPoint(
            x: initialWindowLocation.x + deltaX,
            y: initialWindowLocation.y + deltaY
        )
        
        window.setFrameOrigin(newOrigin)
    }
    
    override func mouseUp(with event: NSEvent) {
        initialMouseLocation = nil
        initialWindowLocation = nil
        
        if let window = window {
            let frame = window.frame
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: "SpotlightWindowFrame")
            UserDefaults.standard.synchronize()
        }
    }
}

// 结果行组件
struct ResultRow: View {
    let result: SearchResult
    @State private var isHovered = false
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if result.type == .calculator {
                Image(systemName: result.type.systemImage)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
            } else {
                Image(nsImage: result.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 14))
                
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text("↩")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color.blue.opacity(0.2) : (isHovered ? Color.blue.opacity(0.1) : Color.clear))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// 文件搜索视图
struct FileSearchView: View {
    @ObservedObject var searchService: SearchService
    @Binding var searchText: String
    @Binding var selectedIndex: Int?
    var onResultSelected: (SearchResult) -> Void
    var onResultsChanged: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if searchService.fileSearchResults.isEmpty {
                // 使用ScrollView保持布局结构一致，避免从无结果到有结果时的布局跳变
                ScrollView {
                    VStack {
                        Text(searchText.isEmpty ? "请输入搜索关键词" : "无匹配文件")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 16)
                    }
                    .frame(minHeight: 120) // 设置最小高度，避免内容过于居中
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(searchService.fileSearchResults.enumerated()), id: \.element.id) { index, result in
                                ResultRow(result: result, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        onResultSelected(result)
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                        .onChange(of: selectedIndex) { _, newIndex in
                            if let index = newIndex {
                                withAnimation {
                                    proxy.scrollTo(index, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchService.searchFiles(query: newValue)
            selectedIndex = searchService.fileSearchResults.isEmpty ? nil : 0
            onResultsChanged()
        }
        .onAppear {
            searchService.searchFiles(query: searchText)
            selectedIndex = searchService.fileSearchResults.isEmpty ? nil : 0
            onResultsChanged()
        }
        .onChange(of: searchService.fileSearchResults) { _, _ in
            onResultsChanged()
        }
    }
}

// 结果列表组件
struct ResultsList: View {
    let categories: [SearchResultCategory]
    let onResultSelected: (SearchResult) -> Void
    let selectedIndex: Int?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(categories) { category in
                        if !category.results.isEmpty {
                            Text(category.title)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            
                            ForEach(Array(category.results.enumerated()), id: \.element.id) { index, result in
                                let globalIndex = categories.prefix(while: { $0.id != category.id })
                                    .reduce(0) { $0 + $1.results.count } + index
                                
                                ResultRow(result: result, isSelected: globalIndex == selectedIndex)
                                    .id(globalIndex)
                                    .onTapGesture {
                                        onResultSelected(result)
                                    }
                            }
                            
                            if category.id != categories.last?.id {
                                Divider()
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .onChange(of: selectedIndex) { _, newIndex in
                    if let index = newIndex {
                        withAnimation {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

// 创建服务引用类，避免在视图上下文外访问StateObject
class ServiceReferences {
    static let shared = ServiceReferences()
    weak var searchService: SearchService?
    weak var aiService: AIService?
}

// 主视图
struct SpotlightView: View {
    @StateObject private var searchService = SearchService()
    @ObservedObject var aiService: AIService
    @State private var searchText = ""
    @State private var selectedIndex: Int?
    @State private var isSearchFocused = false
    @State private var showingAIResponse = false
    @State private var showingFileSearch = false // 新增：是否显示文件搜索视图
    @State private var height: CGFloat = 60
    @State private var prompt: String = ""
    @Environment(\.scenePhase) var scenePhase
    @State private var aiResponseView: AIResponseView? = nil
    
    init(aiService: AIService) {
        self.aiService = aiService
    }
    
    private var shouldShowAIOption: Bool {
        searchText.count >= 3
    }
    
    private var displayResults: [SearchResult] {
        var results: [SearchResult] = []
        
        // 先添加AI入口
        if shouldShowAIOption {
            let aiResult = SearchResult(
                id: UUID(),
                name: "Ask AI: \(searchText)",
                path: "",
                type: .ai,
                category: "AI",
                icon: NSImage(systemSymbolName: "brain.fill", accessibilityDescription: nil) ?? NSImage(),
                subtitle: "使用 AI 回答问题"
            )
            results.append(aiResult)
        }
        
        // 添加应用程序和快捷指令搜索结果
        results.append(contentsOf: searchService.searchResults)
        
        // 最后添加文件搜索入口
        if !searchText.isEmpty {
            let fileSearchResult = SearchResult(
                id: UUID(),
                name: "搜索文件: \(searchText)",
                path: "",
                type: .file,
                category: "文件搜索",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                subtitle: "搜索本地文件"
            )
            results.append(fileSearchResult)
        }
        
        return results
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                searchText: $searchText,
                onClear: {
                    searchText = ""
                    selectedIndex = nil
                    resetWindowHeight()
                }
            )
            .frame(height: 60)
            
            if showingAIResponse {
                AIResponseView(
                    aiService: aiService,
                    prompt: searchText,
                    onEscape: handleEscape,
                    onHeightChange: { contentHeight in
                        DispatchQueue.main.async {
                            adjustWindowHeightWithContent(contentHeight: contentHeight)
                        }
                    },
                    onViewCreated: { view in
                        aiResponseView = view
                    }
                )
            } else if showingFileSearch {
                // 文件搜索二级视图
                FileSearchView(
                    searchService: searchService,
                    searchText: $searchText,
                    selectedIndex: $selectedIndex,
                    onResultSelected: { result in
                        searchService.openResult(result)
                        if let window = NSApp.keyWindow {
                            window.close()
                        }
                    },
                    onResultsChanged: {
                        adjustWindowHeight()
                    }
                )
            } else if !searchText.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    
                    if displayResults.isEmpty {
                        Text("无搜索结果")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                            .frame(height: 60) // 设置最小高度，避免窗口过短
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(displayResults.enumerated()), id: \.element.id) { index, result in
                                        ResultRow(result: result, isSelected: index == selectedIndex)
                                            .id(index)
                                            .onTapGesture {
                                                handleItemClick(result)
                                            }
                                    }
                                }
                                .padding(.vertical, 8)
                                .onChange(of: selectedIndex) { _, newIndex in
                                    if let index = newIndex {
                                        withAnimation {
                                            proxy.scrollTo(index, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            }
        }
        .frame(width: 680, height: height)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .onChange(of: searchText) { _, newValue in
            UserDefaults.standard.set(searchText, forKey: "LastSearchText")
            if !showingAIResponse && !showingFileSearch {
                searchService.search(query: newValue)
                selectedIndex = 0
                // 当搜索文本为空时，重置窗口高度
                if newValue.isEmpty {
                    resetWindowHeight()
                } else {
                    // 仅当不在AI视图和文件搜索视图时才调整窗口高度
                    adjustWindowHeight()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: selectedIndex) { _, newValue in
            if let index = newValue {
                UserDefaults.standard.set(index, forKey: "LastSelectedIndex")
            }
        }
        .onChange(of: searchService.searchResults) { _, _ in
            if !showingFileSearch {
                adjustWindowHeight()
            }
        }
        .onChange(of: aiService.currentResponse) { _, newValue in
            // 不再需要在这里调整高度，已由 onHeightChange 回调处理
        }
        .onChange(of: showingAIResponse) { _, newValue in
            if newValue {
                // 显示 AI 响应时设置一个初始高度
                let baseHeight: CGFloat = 60
                let initialHeight = baseHeight + 150 // 搜索框高度 + 初始内容高度
                height = initialHeight
                DispatchQueue.main.async {
                    if let window = NSApp.keyWindow {
                        var frame = window.frame
                        let oldHeight = frame.size.height
                        frame.origin.y += (oldHeight - initialHeight)
                        frame.size.height = initialHeight
                        window.setFrame(frame, display: true, animate: false)
                    }
                }
            }
        }
        .onChange(of: showingFileSearch) { _, newValue in
            if newValue {
                // 显示文件搜索视图时，重新搜索并确保UI状态正确
                searchService.searchFiles(query: searchText)
                // 稍作延迟，确保结果已加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !searchService.fileSearchResults.isEmpty && selectedIndex == nil {
                        selectedIndex = 0
                    }
                    adjustWindowHeight()
                }
            } else {
                // 返回主视图时，清除文件搜索结果
                searchService.clearResults() // 清除当前文件搜索结果
                searchService.search(query: searchText) // 重新搜索应用
                selectedIndex = 0
                adjustWindowHeight()
            }
        }
        .onChange(of: searchService.fileSearchResults) { _, _ in
            // 监听文件搜索结果变化，调整窗口高度
            if showingFileSearch {
                // 如果文件搜索结果变化，确保有选中状态
                if !searchService.fileSearchResults.isEmpty && selectedIndex == nil {
                    selectedIndex = 0
                }
                adjustWindowHeight()
            }
        }
        .onKeyPress(.escape) { [self] in
            if showingAIResponse {
                showingAIResponse = false
                aiService.cancelStream()
                adjustWindowHeight()
                return .handled
            }
            if showingFileSearch {
                withAnimation {
                    showingFileSearch = false
                }
                adjustWindowHeight()
                return .handled
            }
            if !searchText.isEmpty {
                searchText = ""
                selectedIndex = nil
                return .handled
            }
            if let window = NSApp.keyWindow {
                window.close()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow) { [self] in
            if showingFileSearch {
                if !searchService.fileSearchResults.isEmpty {
                    if let currentIndex = selectedIndex {
                        selectedIndex = max(0, currentIndex - 1)
                    } else {
                        selectedIndex = searchService.fileSearchResults.count - 1
                    }
                }
            } else {
                handleUpArrow()
            }
            return .handled
        }
        .onKeyPress(.downArrow) { [self] in
            if showingFileSearch {
                if !searchService.fileSearchResults.isEmpty {
                    if let currentIndex = selectedIndex {
                        selectedIndex = min(searchService.fileSearchResults.count - 1, currentIndex + 1)
                    } else {
                        selectedIndex = 0
                    }
                }
            } else {
                handleDownArrow()
            }
            return .handled
        }
        .onKeyPress(.return) { [self] in
            if showingFileSearch {
                if let selectedIndex = selectedIndex,
                   selectedIndex >= 0,
                   selectedIndex < searchService.fileSearchResults.count {
                    let result = searchService.fileSearchResults[selectedIndex]
                    searchService.openResult(result)
                    if let window = NSApp.keyWindow {
                        window.close()
                    }
                    return .handled
                }
            } else {
                if let selectedIndex = selectedIndex,
                   selectedIndex >= 0,
                   selectedIndex < displayResults.count {
                    handleSubmit()
                    return .handled
                }
            }
            return .ignored
        }
        .onAppear {
            setupWindow()
            // 保存服务引用
            ServiceReferences.shared.searchService = searchService
            ServiceReferences.shared.aiService = aiService
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .inactive || newPhase == .background {
            if let window = NSApp.keyWindow ?? NSApp.windows.first {
                let frame = window.frame
                UserDefaults.standard.set(NSStringFromRect(frame), forKey: "SpotlightWindowFrame")
                UserDefaults.standard.synchronize()
                window.close()
            }
        }
    }
    
    private func setupWindow() {
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            window.level = .floating
            window.isMovableByWindowBackground = false
            window.hidesOnDeactivate = true
            
            let delegate = SpotlightWindowDelegate()
            window.delegate = delegate
            
            if let frameString = UserDefaults.standard.string(forKey: "SpotlightWindowFrame") {
                let frame = NSRectFromString(frameString)
                window.setFrame(frame, display: true, animate: false)
            }
        }
        
        isSearchFocused = true
        
        if let lastSearchText = UserDefaults.standard.string(forKey: "LastSearchText") {
            searchText = lastSearchText
            searchService.search(query: lastSearchText)
            
            if let lastIndex = UserDefaults.standard.object(forKey: "LastSelectedIndex") as? Int {
                selectedIndex = lastIndex
            }
        }
    }
    
    private func adjustWindowHeight() {
        let baseHeight: CGFloat = 60 // 搜索框高度
        let maxResultsHeight: CGFloat = 500 // 最大结果列表高度
        let resultRowHeight: CGFloat = 44 // 每个结果行的高度
        let emptyStateHeight: CGFloat = 60 // 无结果状态的高度
        let aiViewMinHeight: CGFloat = 120 // AI 视图的最小高度
        let aiViewDefaultHeight: CGFloat = 250 // AI 视图的默认高度
        let aiViewMaxHeight: CGFloat = 500 // AI 视图的最大高度
        let fileSearchMinHeight: CGFloat = 120 // 文件搜索视图的最小高度
        let padding: CGFloat = 16 // 上下内边距
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxWindowHeight = min(screenHeight * 0.8, 800) // 窗口最大高度限制
        
        var newHeight: CGFloat = baseHeight
        
        // 特别为文件搜索视图调整高度逻辑，确保响应更快
        if showingFileSearch {
            if searchService.fileSearchResults.isEmpty {
                // 无结果时使用最小高度
                newHeight += fileSearchMinHeight
            } else {
                // 有结果时根据结果数量计算高度
                let resultsCount = searchService.fileSearchResults.count
                let contentHeight = min(CGFloat(resultsCount) * resultRowHeight + padding, maxResultsHeight)
                newHeight += contentHeight
            }
            
            // 避免频繁更新和高度抖动
            if abs(newHeight - height) > 5 {
                height = newHeight
                
                DispatchQueue.main.async {
                    if let window = NSApp.keyWindow {
                        var frame = window.frame
                        let oldHeight = frame.size.height
                        
                        // 保持窗口顶部位置不变
                        frame.origin.y += (oldHeight - newHeight)
                        frame.size.height = newHeight
                        
                        // 使用非动画方式设置窗口大小
                        window.setFrame(frame, display: true, animate: false)
                    }
                }
            }
            
            return // 提前返回，避免执行后续代码
        }
        
        // 当搜索文本为空时，强制设置为初始高度
        if searchText.isEmpty {
            newHeight = baseHeight
        } else if showingAIResponse {
            // AI 视图显示时，根据内容长度计算高度
            if aiService.currentResponse.isEmpty {
                newHeight += aiViewDefaultHeight // 使用默认高度
            } else {
                // 根据响应长度计算合适的高度
                let responseLength = aiService.currentResponse.count
                let estimatedHeight = max(aiViewMinHeight, min(CGFloat(responseLength) * 0.5, aiViewMaxHeight))
                newHeight += estimatedHeight
            }
        } else if !displayResults.isEmpty {
            // 显示搜索结果时
            if displayResults.isEmpty {
                // 无搜索结果时，显示一个空状态
                newHeight = baseHeight + emptyStateHeight
            } else {
                // 根据搜索结果数量计算高度
                let resultsCount = displayResults.count
                let contentHeight = min(CGFloat(resultsCount) * resultRowHeight, maxResultsHeight)
                newHeight = baseHeight + contentHeight + padding
                
                // 本地搜索时添加一个节流，避免频繁调整高度导致跳动
                if abs(newHeight - height) < 30 {
                    return
                }
            }
        } else {
            // 即使没有搜索关键词时，也设置一个最小高度
            newHeight = max(baseHeight + emptyStateHeight, newHeight)
        }
        
        // 如果搜索文本为空，始终使用初始高度
        if searchText.isEmpty {
            newHeight = baseHeight
        }
        
        // 如果高度发生了有意义的变化，才进行调整
        if abs(newHeight - height) > 10 {
            height = newHeight
            
            // 直接应用到窗口，确保调整生效
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow {
                    var frame = window.frame
                    let oldHeight = frame.size.height
                    
                    // 保持窗口顶部位置不变
                    frame.origin.y += (oldHeight - newHeight)
                    frame.size.height = newHeight
                    
                    // 使用非动画方式设置窗口大小
                    window.setFrame(frame, display: true, animate: false)
                }
            }
        }
    }
    
    private func adjustWindowHeightWithContent(contentHeight: CGFloat) {
        // 基础高度（搜索框）
        let baseHeight: CGFloat = 60
        // 内容边距
        let padding: CGFloat = 36
        // 内容最小高度
        let minContentHeight: CGFloat = 120
        // 屏幕高度
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        // 窗口最大高度限制
        let maxWindowHeight = min(screenHeight * 0.8, 700)
        
        // 确保内容高度不低于最小值
        let effectiveContentHeight = max(contentHeight, minContentHeight)
        
        // 计算新的窗口高度（基础高度 + 内容高度 + 内容边距）
        let newHeight = min(baseHeight + effectiveContentHeight + padding, maxWindowHeight)
        
        // 如果高度变化不大，不进行调整
        if abs(newHeight - height) < 10 {
            return
        }
        
        // 如果新的高度小于当前高度且当前高度合理，不进行调整（允许内容增长，但不收缩）
        if newHeight < height && height < maxWindowHeight && height > (baseHeight + minContentHeight) {
            return
        }
        
        // 更新高度并应用到窗口
        height = newHeight
        
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                var frame = window.frame
                let oldHeight = frame.size.height
                
                // 保持窗口顶部位置不变
                frame.origin.y += (oldHeight - newHeight)
                frame.size.height = newHeight
                
                // 使用非动画方式设置窗口大小
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
    
    func requestFocus() {
        isSearchFocused = true
    }
    
    func resetSearch() {
        searchText = ""
        selectedIndex = nil
        showingAIResponse = false
        showingFileSearch = false
        prompt = ""
        
        // 使用共享引用而不是直接访问StateObject
        DispatchQueue.main.async {
            // 使用ServiceReferences中保存的引用
            ServiceReferences.shared.searchService?.clearResults()
            ServiceReferences.shared.aiService?.cancelStream()
        }
        
        adjustWindowHeight()
    }
    
    private func handleSubmit() {
        if showingAIResponse {
            // 如果已经在 AI 对话界面，则新增一轮对话
            prompt = searchText
            
            // 保持现有窗口高度，避免闪烁
            // 注意：这里不再重置窗口高度
            
            // 发送新请求
            Task { @MainActor in
                if let view = aiResponseView {
                    await view.sendRequest()
                } else {
                    await aiService.streamChat(prompt: searchText)
                }
            }
            return
        }
        
        if let selectedIndex = selectedIndex, selectedIndex < displayResults.count {
            let result = displayResults[selectedIndex]
            if result.type == .ai {
                Task { @MainActor in
                    prompt = searchText
                    showingAIResponse = true
                    adjustWindowHeight()
                }
            } else if result.type == .file && result.path.isEmpty {
                // 如果是文件搜索入口
                withAnimation {
                    showingFileSearch = true
                }
                adjustWindowHeight()
            } else {
                searchService.openResult(result)
                if let window = NSApp.keyWindow {
                    window.close()
                }
            }
        }
    }
    
    private func handleEscape() {
        if showingAIResponse {
            showingAIResponse = false
            aiService.cancelStream()
            // 清除对话历史
            aiService.clearConversation()
            searchText = ""
            adjustWindowHeight()
        } else if showingFileSearch {
            showingFileSearch = false
            adjustWindowHeight()
        } else if let window = NSApp.keyWindow {
            window.close()
        }
    }
    
    private func handleItemClick(_ result: SearchResult) {
        if result.type == .ai {
            Task { @MainActor in
                prompt = searchText
                showingAIResponse = true
                adjustWindowHeight()
            }
        } else if result.type == .file && result.path.isEmpty {
            // 如果是文件搜索入口
            withAnimation {
                showingFileSearch = true
            }
            adjustWindowHeight()
        } else {
            searchService.openResult(result)
            if let window = NSApp.keyWindow {
                window.close()
            }
        }
    }
    
    private func handleUpArrow() {
        if let currentIndex = selectedIndex {
            selectedIndex = max(0, currentIndex - 1)
        } else if !displayResults.isEmpty {
            selectedIndex = displayResults.count - 1
        }
    }
    
    private func handleDownArrow() {
        if let currentIndex = selectedIndex {
            selectedIndex = min(displayResults.count - 1, currentIndex + 1)
        } else if !displayResults.isEmpty {
            selectedIndex = 0
        }
    }
    
    // 重置窗口高度为初始状态
    private func resetWindowHeight() {
        height = 60 // 重置为初始高度
        
        // 直接应用到窗口
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                var frame = window.frame
                let oldHeight = frame.size.height
                frame.origin.y += (oldHeight - 60)
                frame.size.height = 60
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}

// 视觉效果视图
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// 添加窗口代理类来处理失焦
class SpotlightWindowDelegate: NSObject, NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // 保存窗口位置并关闭窗口
        let frame = window.frame
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "SpotlightWindowFrame")
        UserDefaults.standard.synchronize()
        window.close()
    }
} 
