import Foundation
import AppKit

// 应用信息结构体
struct AppInfo: Identifiable {
    let id = UUID()
    let name: String
    let localizedNames: [String]  // 存储多语言名称
    let path: String
    let bundleID: String?
    let icon: NSImage
    let lastUsedDate: Date?
    let isSystemApp: Bool
    
    init(name: String, localizedNames: [String] = [], path: String, bundleID: String? = nil, icon: NSImage, lastUsedDate: Date? = nil, isSystemApp: Bool) {
        self.name = name
        self.localizedNames = localizedNames
        self.path = path
        self.bundleID = bundleID
        self.icon = icon
        self.lastUsedDate = lastUsedDate
        self.isSystemApp = isSystemApp
    }
}

class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var fileSearchResults: [SearchResult] = []
    
    // 应用信息缓存
    private var allApps: [AppInfo] = []
    private var allShortcuts: [AppInfo] = []
    
    private let applicationCategory = "应用程序"
    private let shortcutsCategory = "快捷指令"
    private let recentFilesCategory = "最近文件"
    private let maxRecentFiles = 20
    private var metadataQuery: NSMetadataQuery?
    
    // 系统应用目录列表
    private let systemAppDirectories = [
        "/Applications",
        "/System/Applications",
        "/System/Library/CoreServices/Finder.app",
        "/System/Library/CoreServices/System Preferences.app",
        "/System/Library/CoreServices/System Settings.app"
    ]
    
    // 快捷指令存储目录
    private let shortcutDirectories = [
        "~/Library/Shortcuts",
        "/private/var/mobile/Library/Shortcuts"
    ]
    
    init() {
        DispatchQueue.main.async {
            self.loadAllApps()
        }
    }
    
    deinit {
        print("[SearchService] 释放")
        cleanup()
    }
    
    private func cleanup() {
        print("[SearchService] 清理资源")
        if let query = metadataQuery {
            query.stop()
            NotificationCenter.default.removeObserver(self)
            metadataQuery = nil
        }
    }
    
    // 获取应用的多语言名称
    private func getLocalizedAppNames(forPath path: String) -> [String] {
        var localizedNames: [String] = []
        
        guard let bundle = Bundle(path: path) else {
            return localizedNames
        }
        
        // 获取主要本地化名称
        if let displayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String {
            localizedNames.append(displayName)
        } else if let bundleName = bundle.localizedInfoDictionary?["CFBundleName"] as? String {
            localizedNames.append(bundleName)
        }
        
        // 尝试获取主要Info.plist中的名称
        if let displayName = bundle.infoDictionary?["CFBundleDisplayName"] as? String, !localizedNames.contains(displayName) {
            localizedNames.append(displayName)
        } else if let bundleName = bundle.infoDictionary?["CFBundleName"] as? String, !localizedNames.contains(bundleName) {
            localizedNames.append(bundleName)
        }
        
        // 获取不同语言版本的名称
        let lprojPaths = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: bundle.bundlePath), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        
        for path in lprojPaths {
            let pathExtension = path.pathExtension
            if pathExtension.hasSuffix("lproj") {
                let language = pathExtension.replacingOccurrences(of: ".lproj", with: "")
                
                // 尝试加载该语言的InfoPlist.strings
                let stringsPath = path.appendingPathComponent("InfoPlist.strings")
                if let strings = NSDictionary(contentsOf: stringsPath) {
                    if let displayName = strings["CFBundleDisplayName"] as? String, !localizedNames.contains(displayName) {
                        localizedNames.append(displayName)
                    } else if let bundleName = strings["CFBundleName"] as? String, !localizedNames.contains(bundleName) {
                        localizedNames.append(bundleName)
                    }
                }
            }
        }
        
        return localizedNames
    }
    
    // 加载所有应用信息
    private func loadAllApps() {
        print("[SearchService] 开始加载应用信息...")
        self.setupMetadataQuery()
        
        // 加载快捷指令
        self.loadShortcutsUsingCLI()
        
        guard let metadataQuery = self.metadataQuery else {
            print("[SearchService] 错误: 元数据查询对象为空")
            return
        }
        
        // 移除现有的观察者
        NotificationCenter.default.removeObserver(self)
        
        // 应用类型谓词
        let appTypePredicate = NSPredicate(format: "kMDItemContentType = 'com.apple.application-bundle'")
        
        // 合并谓词 - 只搜索应用程序，快捷指令通过CLI获取
        metadataQuery.predicate = appTypePredicate
        
        print("[SearchService] 设置查询谓词: \(metadataQuery.predicate?.description ?? "无")")
        
        // 设置完成通知处理
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInitialAppLoad),
            name: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery
        )
        
        print("[SearchService] 开始执行初始查询...")
        metadataQuery.start()
    }
    
    // 使用CLI命令获取快捷指令列表
    private func loadShortcutsUsingCLI() {
        print("[SearchService] 开始使用系统CLI获取快捷指令...")
        
        // 清空现有快捷指令
        self.allShortcuts = []
        
        // 先尝试获取Shortcuts应用图标作为备选
        let shortcutsAppIcon = getShortcutsAppIcon()
        
        // 执行 shortcuts list 命令
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["list"]
        
        // 在macOS Ventura及以上版本，shortcuts命令在/usr/bin/目录下
        let shortcutsPath = "/usr/bin/shortcuts"
        
        if FileManager.default.fileExists(atPath: shortcutsPath) {
            task.executableURL = URL(fileURLWithPath: shortcutsPath)
            
            do {
                print("[SearchService] 执行命令: shortcuts list")
                try task.run()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    if output.isEmpty {
                        print("[SearchService] 命令未返回任何快捷指令")
                        loadDefaultShortcuts()
                    } else {
                        // 解析输出，格式通常为每行一个快捷指令名
                        let shortcuts = parseShortcutsOutput(output)
                        print("[SearchService] 成功获取\(shortcuts.count)个快捷指令")
                        
                        for name in shortcuts {
                            // 创建一个快捷指令图标 - 如果有Shortcuts应用图标则使用它
                            let icon = shortcutsAppIcon ?? createShortcutIcon(withColor: "blue")
                            
                            let commandPath = "shortcuts run \"\(name)\""
                            
                            let appInfo = AppInfo(
                                name: name,
                                localizedNames: [],
                                path: commandPath,
                                bundleID: nil,
                                icon: icon,
                                lastUsedDate: nil,
                                isSystemApp: false
                            )
                            self.allShortcuts.append(appInfo)
                        }
                    }
                } else {
                    print("[SearchService] 无法解析命令输出")
                    loadDefaultShortcuts()
                }
            } catch {
                print("[SearchService] 执行命令失败: \(error)")
                loadDefaultShortcuts()
            }
        } else {
            print("[SearchService] 未找到shortcuts命令，可能是macOS版本低于Ventura")
            loadDefaultShortcuts()
        }
    }
    
    // 获取Shortcuts应用图标
    private func getShortcutsAppIcon() -> NSImage? {
        let possiblePaths = [
            "/System/Applications/Shortcuts.app",
            "/Applications/Shortcuts.app"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                print("[SearchService] 获取到Shortcuts应用图标")
                return icon
            }
        }
        
        print("[SearchService] 未找到Shortcuts应用图标")
        return nil
    }
    
    // 解析shortcuts list命令的输出
    private func parseShortcutsOutput(_ output: String) -> [String] {
        // 按行分割
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // 移除可能的标题行或提示行
        let shortcuts = lines.filter {
            // 排除包含"Name"、"Type"等可能的标题行
            !$0.lowercased().contains("name:") &&
            !$0.lowercased().contains("type:") &&
            !$0.lowercased().contains("folder:") &&
            !$0.hasPrefix("-") && 
            !$0.hasPrefix("=")
        }
        
        return shortcuts
    }
    
    // 加载默认的快捷指令列表作为备选方案
    private func loadDefaultShortcuts() {
        print("[SearchService] 不加载默认快捷指令列表，返回空列表")
        // 不再创建默认快捷指令列表
        self.allShortcuts = []
    }
    
    // 根据颜色名称创建快捷指令图标
    private func createShortcutIcon(withColor colorName: String) -> NSImage {
        // 通用图标颜色
        var color: NSColor = .systemBlue
        
        // 根据颜色名称设置实际颜色
        switch colorName.lowercased() {
        case "blue": color = .systemBlue
        case "red": color = .systemRed
        case "pink": color = .systemPink
        case "orange": color = .systemOrange
        case "yellow": color = .systemYellow
        case "green": color = .systemGreen
        case "teal", "mint": color = .systemTeal
        case "indigo", "purple": color = .systemIndigo
        case "gray", "grey": color = .systemGray
        default: break
        }
        
        // 创建图像
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        
        color.setFill()
        path.fill()
        
        // 绘制标志性图案 (简单的"⚙" 或 "〉" 符号)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        
        let symbol = "〉"
        let textSize = symbol.size(withAttributes: textAttributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        symbol.draw(in: textRect, withAttributes: textAttributes)
        
        image.unlockFocus()
        
        return image
    }
    
    @objc private func handleInitialAppLoad(notification: Notification) {
        print("[SearchService] 接收到初始应用加载完成通知")
        guard let query = notification.object as? NSMetadataQuery else {
            print("[SearchService] 错误: 通知对象不是NSMetadataQuery")
            return
        }
        
        query.disableUpdates()
        print("[SearchService] 查询结果数量: \(query.results.count)")
        
        // 只清空应用数据，保留快捷指令
        self.allApps = []
        
        let contentTypeAttr = kMDItemContentType as String
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { 
                print("[SearchService] 警告: 跳过缺少路径的项目")
                continue 
            }
            
            // 获取内容类型，用于区分应用和快捷指令
            let contentType = item.value(forAttribute: contentTypeAttr) as? String
            
            // 获取应用名称，使用显示名称
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            
            // 移除显示名称末尾的 .app 后缀（如果有）
            let cleanDisplayName = displayName.hasSuffix(".app") ? 
                displayName.replacingOccurrences(of: ".app", with: "") : 
                displayName
            
            let icon = NSWorkspace.shared.icon(forFile: path)
            let lastUsedDate = item.value(forAttribute: kMDItemLastUsedDate as String) as? Date
            
            // 处理应用程序
            if contentType == "com.apple.application-bundle" || path.hasSuffix(".app") {
                // 获取Bundle ID
                let bundleID = Bundle(path: path)?.bundleIdentifier
                
                // 获取应用多语言名称
                var localizedNames = getLocalizedAppNames(forPath: path)
                // 确保主名称也在列表中
                if !localizedNames.contains(cleanDisplayName) {
                    localizedNames.append(cleanDisplayName)
                }
                
                let isSystemApp = isInSystemDirectory(path)
                let appInfo = AppInfo(
                    name: cleanDisplayName,
                    localizedNames: localizedNames,
                    path: path,
                    bundleID: bundleID,
                    icon: icon,
                    lastUsedDate: lastUsedDate,
                    isSystemApp: isSystemApp
                )
                self.allApps.append(appInfo)
                print("[SearchService] 添加应用: \(cleanDisplayName), 多语言名称: \(localizedNames.joined(separator: ", "))")
            }
            // 处理快捷指令
            else if contentType == "com.apple.shortcuts.shortcut" || isShortcutFile(path) {
                let appInfo = AppInfo(
                    name: cleanDisplayName,
                    path: path,
                    bundleID: nil,
                    icon: icon,
                    lastUsedDate: lastUsedDate,
                    isSystemApp: false
                )
                self.allShortcuts.append(appInfo)
                print("[SearchService] 添加快捷指令: \(cleanDisplayName), 路径: \(path)")
            }
        }
        
        print("[SearchService] 预加载完成: \(self.allApps.count) 个应用, \(self.allShortcuts.count) 个快捷指令")
        
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        
        // 设置文件搜索查询
        self.setupMetadataQuery()
    }
    
    // 检查文件是否是快捷指令文件
    private func isShortcutFile(_ path: String) -> Bool {
        // 检查路径是否在快捷指令目录中或具有快捷指令文件扩展名
        if path.hasSuffix(".shortcut") {
            return true
        }
        
        for dir in shortcutDirectories {
            let expandedDir = (dir as NSString).expandingTildeInPath
            if path.hasPrefix(expandedDir) {
                return true
            }
        }
        
        // 检查特定的快捷指令应用路径
        if path.contains("/com.apple.shortcuts/") && path.contains("/Shortcuts/") {
            return true
        }
        
        return false
    }
    
    private func setupMetadataQuery() {
        print("[SearchService] 设置元数据查询...")
        if let query = metadataQuery {
            query.stop()
            NotificationCenter.default.removeObserver(self)
        }
        
        let query = NSMetadataQuery()
        query.searchScopes = [
            NSMetadataQueryLocalComputerScope,
            NSMetadataQueryUserHomeScope
        ]
        
        query.valueListAttributes = [
            kMDItemDisplayName as String,
            kMDItemPath as String,
            kMDItemContentType as String,
            kMDItemKind as String,
            kMDItemFSName as String,
            kMDItemLastUsedDate as String
        ]
        
        query.sortDescriptors = [NSSortDescriptor(key: kMDItemLastUsedDate as String, ascending: false)]
        query.notificationBatchingInterval = 0.1
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryResults),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        
        self.metadataQuery = query
    }
    
    // 默认搜索只搜索系统目录下的应用程序和快捷指令
    func search(query: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("[SearchService] 执行搜索: \"\(query)\", 应用缓存: \(self.allApps.count)个, 快捷指令缓存: \(self.allShortcuts.count)个")
            
            if query.isEmpty {
                self.searchResults = []
                self.categories = []
                return
            }
            
            // 如果应用列表为空，尝试立即加载
            if self.allApps.isEmpty && self.allShortcuts.isEmpty {
                print("[SearchService] 警告: 应用缓存为空，尝试重新加载")
                self.loadAllApps()
                
                // 为防止应用加载期间没有结果显示，这里可以返回一个临时结果
                let tempResult = SearchResult(
                    id: UUID(),
                    name: "正在加载应用列表...",
                    path: "",
                    type: .application,
                    category: self.applicationCategory,
                    icon: NSImage(named: NSImage.applicationIconName) ?? NSImage(),
                    subtitle: "请稍候",
                    lastUsedDate: nil,
                    relevanceScore: 100
                )
                self.searchResults = [tempResult]
                self.categories = [SearchResultCategory(
                    id: "loading",
                    title: "加载中",
                    results: [tempResult]
                )]
                return
            }
            
            let searchQueryText = query.lowercased()
            
            // 在内存中过滤系统应用
            let filteredApps = self.allApps
                .filter { $0.isSystemApp }
                .filter { app in
                    self.appMatchesQuery(app: app, query: searchQueryText)
                }
                .map { app -> SearchResult in
                    let relevanceScore = self.calculateRelevanceScore(app: app, query: searchQueryText)
                    return SearchResult(
                        id: UUID(),
                        name: app.name,
                        path: app.path,
                        type: .application,
                        category: self.applicationCategory,
                        icon: app.icon,
                        subtitle: "",  // 移除路径显示
                        lastUsedDate: app.lastUsedDate,
                        relevanceScore: relevanceScore
                    )
                }
            
            // 在内存中过滤快捷指令
            let filteredShortcuts = self.allShortcuts
                .filter { app in
                    self.appMatchesQuery(app: app, query: searchQueryText)
                }
                .map { app -> SearchResult in
                    let relevanceScore = self.calculateRelevanceScore(app: app, query: searchQueryText)
                    return SearchResult(
                        id: UUID(),
                        name: app.name,
                        path: app.path,
                        type: .shortcut,
                        category: self.shortcutsCategory,
                        icon: app.icon,
                        subtitle: "",  // 移除"快捷指令"文字
                        lastUsedDate: app.lastUsedDate,
                        relevanceScore: relevanceScore
                    )
                }
            
            // 对结果进行同样的排序
            let sortedApps = self.sortSearchResults(filteredApps)
            let sortedShortcuts = self.sortSearchResults(filteredShortcuts)
            
            let allResults = sortedApps + sortedShortcuts
            
            print("[SearchService] 查询 \"\(query)\" 找到 \(sortedApps.count) 个应用, \(sortedShortcuts.count) 个快捷指令")
            
            // 更新结果
            self.searchResults = allResults
            
            var categories: [SearchResultCategory] = []
            if !sortedApps.isEmpty {
                categories.append(SearchResultCategory(
                    id: self.applicationCategory,
                    title: self.applicationCategory,
                    results: sortedApps
                ))
            }
            if !sortedShortcuts.isEmpty {
                categories.append(SearchResultCategory(
                    id: self.shortcutsCategory,
                    title: self.shortcutsCategory,
                    results: sortedShortcuts
                ))
            }
            
            self.categories = categories
        }
    }
    
    // 判断应用是否匹配查询
    private func appMatchesQuery(app: AppInfo, query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        
        // 检查主名称
        if appNameMatchesQuery(appName: app.name, query: lowercaseQuery) {
            return true
        }
        
        // 检查所有本地化名称
        for name in app.localizedNames {
            if appNameMatchesQuery(appName: name, query: lowercaseQuery) {
                return true
            }
        }
        
        return false
    }
    
    // 判断应用名称是否匹配查询
    private func appNameMatchesQuery(appName: String, query: String) -> Bool {
        let lowercaseAppName = appName.lowercased()
        let lowercaseQuery = query.lowercased()
        
        // 完全匹配
        if lowercaseAppName == lowercaseQuery {
            return true
        }
        
        // 前缀匹配
        if lowercaseAppName.hasPrefix(lowercaseQuery) {
            return true
        }
        
        // 忽略英文单词之间的空格的匹配
        let appNameNoSpaces = lowercaseAppName.replacingOccurrences(of: " ", with: "")
        let queryNoSpaces = lowercaseQuery.replacingOccurrences(of: " ", with: "")
        
        if appNameNoSpaces == queryNoSpaces || appNameNoSpaces.hasPrefix(queryNoSpaces) {
            return true
        }
        
        // 单词匹配（对英文更有效）
        let words = lowercaseAppName.components(separatedBy: .whitespacesAndNewlines)
        for word in words where word.hasPrefix(lowercaseQuery) {
            return true
        }
        
        // 中文匹配 - 对中文字符进行特殊处理
        if containsChineseCharacters(query) {
            // 对于中文查询，支持任意位置匹配
            if lowercaseAppName.contains(lowercaseQuery) {
                return true
            }
        }
        // 英文匹配，至少3个字符才做包含匹配
        else if query.count >= 3 && lowercaseAppName.contains(lowercaseQuery) {
            return true
        }
        
        return false
    }
    
    // 检查字符串是否包含中文字符
    private func containsChineseCharacters(_ text: String) -> Bool {
        let pattern = "\\p{Han}"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: text.utf16.count)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        return false
    }
    
    // 排序搜索结果
    private func sortSearchResults(_ results: [SearchResult]) -> [SearchResult] {
        results.sorted { (result1, result2) in
            // 首先比较最近使用时间
            if let date1 = result1.lastUsedDate, let date2 = result2.lastUsedDate {
                if date1 != date2 {
                    return date1 > date2
                }
            } else if result1.lastUsedDate != nil {
                return true
            } else if result2.lastUsedDate != nil {
                return false
            }
            
            // 时间相同或无法比较时，比较相关性分数
            return result1.relevanceScore > result2.relevanceScore
        }
    }
    
    // 搜索文件，包括系统目录外的应用程序
    func searchFiles(query: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if query.isEmpty {
                self.fileSearchResults = []
                return
            }
            
            let searchQueryText = query.lowercased()
            
            // 在内存中过滤非系统应用
            let filteredNonSystemApps = self.allApps
                .filter { !$0.isSystemApp }
                .filter { app in
                    self.appMatchesQuery(app: app, query: searchQueryText)
                }
                .map { app -> SearchResult in
                    let relevanceScore = self.calculateRelevanceScore(app: app, query: searchQueryText)
                    return SearchResult(
                        id: UUID(),
                        name: app.name,
                        path: app.path,
                        type: .application,
                        category: "其他应用程序",
                        icon: app.icon,
                        subtitle: "",  // 移除路径显示
                        lastUsedDate: app.lastUsedDate,
                        relevanceScore: relevanceScore
                    )
                }
            
            let sortedNonSystemApps = self.sortSearchResults(filteredNonSystemApps)
            
            // 使用元数据查询搜索文件
            guard let metadataQuery = self.metadataQuery else {
                self.fileSearchResults = sortedNonSystemApps
                return
            }
            
            // 文件搜索 - 非应用文件
            let fileNamePredicates = self.buildSearchPredicates(forQuery: query)
            let nonAppTypePredicate = NSPredicate(format: "kMDItemContentType != 'com.apple.application-bundle'")
            let nonAppFilePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [nonAppTypePredicate, fileNamePredicates])
            
            metadataQuery.predicate = nonAppFilePredicate
            
            // 使用自定义通知来处理文件搜索结果
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: metadataQuery)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleFileQueryResults),
                name: .NSMetadataQueryDidFinishGathering,
                object: metadataQuery
            )
            
            // 保存非系统应用结果，等待文件搜索完成后合并
            self.fileSearchResults = sortedNonSystemApps
            metadataQuery.start()
        }
    }
    
    // 计算搜索相关性分数
    private func calculateRelevanceScore(app: AppInfo, query: String) -> Int {
        let lowercaseQuery = query.lowercased()
        let score = calculateRelevanceScore(appName: app.name, query: lowercaseQuery)
        
        // 如果主名称匹配度不高，检查本地化名称
        if score < 70 {
            var highestScore = score
            for name in app.localizedNames {
                let localizedScore = calculateRelevanceScore(appName: name, query: lowercaseQuery)
                if localizedScore > highestScore {
                    highestScore = localizedScore
                }
            }
            return highestScore
        }
        
        return score
    }
    
    // 计算搜索相关性分数
    private func calculateRelevanceScore(appName: String, query: String) -> Int {
        let lowercaseAppName = appName.lowercased()
        let lowercaseQuery = query.lowercased()
        
        // 完全匹配，最高优先级
        if lowercaseAppName == lowercaseQuery {
            return 100
        }
        
        // 开头匹配，次高优先级
        if lowercaseAppName.hasPrefix(lowercaseQuery) {
            return 80
        }
        
        // 单词开头匹配，例如在"Safari浏览器"中匹配"Safari"
        let words = lowercaseAppName.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            if word.hasPrefix(lowercaseQuery) {
                return 70
            }
        }
        
        // 中文特殊处理 - 为中文查询提供更高的包含匹配分数
        if containsChineseCharacters(query) {
            if lowercaseAppName.contains(lowercaseQuery) {
                // 字符匹配在靠前的位置，根据匹配位置给分
                if let range = lowercaseAppName.range(of: lowercaseQuery) {
                    let distance = lowercaseAppName.distance(from: lowercaseAppName.startIndex, to: range.lowerBound)
                    return max(30, 65 - distance) // 中文匹配位置越靠前，分数越高
                }
                return 60 // 默认中文包含匹配分数
            }
        }
        
        // 字符匹配在靠前的位置，根据匹配位置给分
        if let range = lowercaseAppName.range(of: lowercaseQuery) {
            let distance = lowercaseAppName.distance(from: lowercaseAppName.startIndex, to: range.lowerBound)
            return max(10, 60 - distance * 2) // 匹配位置越靠前，分数越高
        }
        
        // 默认分数
        return 0
    }
    
    @objc private func handleQueryResults(notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        
        query.disableUpdates()
        
        var applications: [SearchResult] = []
        var shortcuts: [SearchResult] = []
        let searchQueryText = query.predicate?.description.components(separatedBy: "\"").filter { !$0.contains("kMDItem") }.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            
            // 获取应用名称，使用显示名称
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            
            // 移除显示名称末尾的 .app 后缀（如果有）
            let cleanDisplayName = displayName.hasSuffix(".app") ? 
                displayName.replacingOccurrences(of: ".app", with: "") : 
                displayName
            
            let icon = NSWorkspace.shared.icon(forFile: path)
            let lastUsedDate = item.value(forAttribute: kMDItemLastUsedDate as String) as? Date
            
            // 检查应用程序是否在系统目录下
            if path.hasSuffix(".app") && isInSystemDirectory(path) {
                // 计算相关性分数
                let relevanceScore = calculateRelevanceScore(appName: cleanDisplayName, query: searchQueryText)
                
                let result = SearchResult(
                    id: UUID(),
                    name: cleanDisplayName,
                    path: path,
                    type: .application,
                    category: applicationCategory,
                    icon: icon,
                    subtitle: "",  // 移除路径显示
                    lastUsedDate: lastUsedDate,
                    relevanceScore: relevanceScore
                )
                applications.append(result)
            } else if isShortcutFile(path) {
                // 快捷指令处理
                let relevanceScore = calculateRelevanceScore(appName: cleanDisplayName, query: searchQueryText)
                
                let result = SearchResult(
                    id: UUID(),
                    name: cleanDisplayName,
                    path: path,
                    type: .shortcut,
                    category: shortcutsCategory,
                    icon: icon,
                    subtitle: "",  // 移除"快捷指令"文字
                    lastUsedDate: lastUsedDate,
                    relevanceScore: relevanceScore
                )
                shortcuts.append(result)
            }
        }
        
        // 使用两级排序：首先按最近使用时间（可能为nil），然后按匹配相关性
        applications.sort { (result1, result2) in
            // 首先比较最近使用时间
            if let date1 = result1.lastUsedDate, let date2 = result2.lastUsedDate {
                if date1 != date2 {
                    return date1 > date2
                }
            } else if result1.lastUsedDate != nil {
                return true
            } else if result2.lastUsedDate != nil {
                return false
            }
            
            // 时间相同或无法比较时，比较相关性分数
            return result1.relevanceScore > result2.relevanceScore
        }
        
        // 同样为快捷指令排序
        shortcuts.sort { (result1, result2) in
            if let date1 = result1.lastUsedDate, let date2 = result2.lastUsedDate {
                if date1 != date2 {
                    return date1 > date2
                }
            } else if result1.lastUsedDate != nil {
                return true
            } else if result2.lastUsedDate != nil {
                return false
            }
            
            return result1.relevanceScore > result2.relevanceScore
        }
        
        let allResults = applications + shortcuts
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.searchResults = allResults
            
            var categories: [SearchResultCategory] = []
            if !applications.isEmpty {
                categories.append(SearchResultCategory(
                    id: self.applicationCategory,
                    title: self.applicationCategory,
                    results: applications
                ))
            }
            if !shortcuts.isEmpty {
                categories.append(SearchResultCategory(
                    id: self.shortcutsCategory,
                    title: self.shortcutsCategory,
                    results: shortcuts
                ))
            }
            
            self.categories = categories
        }
        
        query.enableUpdates()
        
        // 恢复原始查询结果处理器
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryResults),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
    }
    
    // 检查路径是否在指定的系统目录下
    private func isInSystemDirectory(_ path: String) -> Bool {
        for directory in systemAppDirectories {
            if path.hasPrefix(directory) {
                return true
            }
        }
        return false
    }
    
    // 处理文件搜索结果的方法
    @objc private func handleFileQueryResults(notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        
        query.disableUpdates()
        
        var files: [SearchResult] = []
        var processedItemCount = 0
        let searchQueryText = query.predicate?.description.components(separatedBy: "\"").filter { !$0.contains("kMDItem") }.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String,
                  processedItemCount < maxRecentFiles else { break }
            
            // 获取应用名称，使用显示名称
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            
            // 移除显示名称末尾的 .app 后缀（如果有）
            let cleanDisplayName = displayName.hasSuffix(".app") ? 
                displayName.replacingOccurrences(of: ".app", with: "") : 
                displayName
            
            let icon = NSWorkspace.shared.icon(forFile: path)
            let lastUsedDate = item.value(forAttribute: kMDItemLastUsedDate as String) as? Date
            
            let relevanceScore = calculateRelevanceScore(appName: cleanDisplayName, query: searchQueryText)
            
            let result = SearchResult(
                id: UUID(),
                name: cleanDisplayName,
                path: path,
                type: .file,
                category: recentFilesCategory,
                icon: icon,
                subtitle: "",  // 移除路径显示
                lastUsedDate: lastUsedDate,
                relevanceScore: relevanceScore
            )
            files.append(result)
            processedItemCount += 1
        }
        
        // 对文件进行两级排序
        files.sort { (result1, result2) in
            if let date1 = result1.lastUsedDate, let date2 = result2.lastUsedDate {
                if date1 != date2 {
                    return date1 > date2
                }
            } else if result1.lastUsedDate != nil {
                return true
            } else if result2.lastUsedDate != nil {
                return false
            }
            
            return result1.relevanceScore > result2.relevanceScore
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 获取当前的非系统应用结果
            let nonSystemApps = self.fileSearchResults
            // 合并非系统应用和文件结果
            self.fileSearchResults = nonSystemApps + files
        }
        
        query.enableUpdates()
        
        // 恢复原始查询结果处理器
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryResults),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
    }
    
    // 覆盖原有的打开结果方法，添加对快捷指令命令的支持
    func openResult(_ result: SearchResult) {
        if result.type == .shortcut {
            // 对于快捷指令，使用Process执行命令
            if result.path.hasPrefix("shortcuts run") {
                runShortcutCommand(result.path)
                return
            }
        }
        
        // 对于其他类型，使用默认方法打开
        NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
    }
    
    // 执行快捷指令命令
    private func runShortcutCommand(_ command: String) {
        // 解析命令字符串
        let components = command.components(separatedBy: " ")
        if components.count < 3 || components[0] != "shortcuts" || components[1] != "run" {
            print("[SearchService] 错误: 无效的快捷指令命令: \(command)")
            return
        }
        
        // 重建快捷指令名称（可能包含空格）
        let shortcutName = components[2...].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        print("[SearchService] 执行快捷指令: \(shortcutName)")
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["run", shortcutName]
        
        // 设置可执行文件路径
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        
        do {
            try task.run()
            print("[SearchService] 快捷指令执行已启动")
        } catch {
            print("[SearchService] 执行快捷指令失败: \(error)")
        }
    }
    
    func clearResults() {
        DispatchQueue.main.async {
            self.searchResults = []
            self.categories = []
            self.fileSearchResults = []
        }
    }
    
    // 为搜索字符串构建更精确的谓词
    private func buildSearchPredicates(forQuery query: String) -> NSPredicate {
        let queryWords = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        
        if queryWords.isEmpty {
            return NSPredicate(value: false)
        }
        
        var predicates: [NSPredicate] = []
        
        // 1. 精确匹配 - 应用名称完全等于查询
        let exactNamePredicate = NSPredicate(format: "kMDItemDisplayName ==[cd] %@", query)
        predicates.append(exactNamePredicate)
        
        // 2. 应用名开头匹配 - 比普通包含更有针对性
        let nameStartsPredicate = NSPredicate(format: "kMDItemDisplayName BEGINSWITH[cd] %@", query)
        predicates.append(nameStartsPredicate)
        
        // 3. 文件名开头匹配 - 比普通包含更有针对性
        let fileNameStartsPredicate = NSPredicate(format: "kMDItemFSName BEGINSWITH[cd] %@", query)
        predicates.append(fileNameStartsPredicate)
        
        // 4. 单词匹配 - 匹配应用名称中的单词，更精确
        for word in queryWords {
            if word.count >= 2 { // 只匹配长度大于等于2的单词，避免匹配到常见字母如"a"
                // 匹配以这个词开头的应用
                let wordStartPredicate = NSPredicate(format: "kMDItemDisplayName BEGINSWITH[cd] %@", word)
                predicates.append(wordStartPredicate)
                
                // 不使用 MATCHES 操作符，NSMetadataQuery 不支持正则表达式
                // 改用单独的空格匹配检查，尝试匹配独立单词
                if word.count >= 3 {
                    let wordWithSpacePredicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", " " + word + " ")
                    predicates.append(wordWithSpacePredicate)
                    
                    // 匹配位于开头的单词（前面没有字符）
                    let wordAtStartPredicate = NSPredicate(format: "kMDItemDisplayName BEGINSWITH[cd] %@", word + " ")
                    predicates.append(wordAtStartPredicate)
                    
                    // 匹配位于结尾的单词（后面没有字符）
                    let wordAtEndPredicate = NSPredicate(format: "kMDItemDisplayName ENDSWITH[cd] %@", " " + word)
                    predicates.append(wordAtEndPredicate)
                }
            }
        }
        
        // 5. 宽松匹配 - 为长查询字符串提供匹配机会
        if query.count >= 3 { // 只对长度大于等于3的查询使用CONTAINS
            let containsNamePredicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", query)
            predicates.append(containsNamePredicate)
            
            // 只匹配不以 .app 结尾的文件名
            if !query.lowercased().hasSuffix(".app") {
                let containsFileNamePredicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", query)
                predicates.append(containsFileNamePredicate)
            }
        }
        
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }
    
    // 为快捷指令构建搜索谓词
    private func buildSearchPredicatesForShortcuts(query: String) -> NSPredicate {
        let queryWords = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        
        if queryWords.isEmpty {
            return NSPredicate(value: false)
        }
        
        var predicates: [NSPredicate] = []
        
        // 精确匹配
        let exactPredicate = NSPredicate(format: "(kMDItemDisplayName ==[cd] %@) AND (kMDItemPath CONTAINS[cd] 'Shortcuts')", query)
        predicates.append(exactPredicate)
        
        // 开头匹配
        let startsPredicate = NSPredicate(format: "(kMDItemDisplayName BEGINSWITH[cd] %@) AND (kMDItemPath CONTAINS[cd] 'Shortcuts')", query)
        predicates.append(startsPredicate)
        
        // 长查询的包含匹配
        if query.count >= 3 {
            let containsPredicate = NSPredicate(format: "(kMDItemDisplayName CONTAINS[cd] %@) AND (kMDItemPath CONTAINS[cd] 'Shortcuts')", query)
            predicates.append(containsPredicate)
        }
        
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }
} 