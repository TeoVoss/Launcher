import Foundation
import AppKit

class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var fileSearchResults: [SearchResult] = []
    
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
        "/System/Library/CoreServices/Finder.app/Contents/Applications"
    ]
    
    init() {
        DispatchQueue.main.async {
            self.setupMetadataQuery()
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
    
    private func setupMetadataQuery() {
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
            
            if let currentQuery = self.metadataQuery {
                currentQuery.stop()
            }
            
            if query.isEmpty {
                self.searchResults = []
                self.categories = []
                return
            }
            
            guard let metadataQuery = self.metadataQuery else { return }
            
            // 构建应用名称匹配谓词
            let appNamePredicates = buildSearchPredicates(forQuery: query)
            
            // 应用类型谓词
            let appTypePredicate = NSPredicate(format: "kMDItemContentType = 'com.apple.application-bundle'")
            
            // 组合应用类型和名称匹配谓词
            let appPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [appTypePredicate, appNamePredicates])
            
            // 添加快捷指令搜索
            let shortcutsPredicate = buildSearchPredicatesForShortcuts(query: query)
            
            metadataQuery.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [appPredicate, shortcutsPredicate])
            
            metadataQuery.start()
        }
    }
    
    // 搜索文件，包括系统目录外的应用程序
    func searchFiles(query: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let currentQuery = self.metadataQuery {
                currentQuery.stop()
            }
            
            if query.isEmpty {
                self.fileSearchResults = []
                return
            }
            
            guard let metadataQuery = self.metadataQuery else { return }
            
            // 文件搜索 - 非应用文件
            let fileNamePredicates = buildSearchPredicates(forQuery: query)
            let nonAppTypePredicate = NSPredicate(format: "kMDItemContentType != 'com.apple.application-bundle'")
            let nonAppFilePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [nonAppTypePredicate, fileNamePredicates])
            
            // 搜索不在系统目录列表中的应用程序
            var nonSystemAppPredicates: [NSPredicate] = []
            let appTypePredicate = NSPredicate(format: "kMDItemContentType = 'com.apple.application-bundle'")
            let appNamePredicates = buildSearchPredicates(forQuery: query)
            
            // 组合应用类型和名称匹配谓词
            let appBasePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [appTypePredicate, appNamePredicates])
            
            // 为每个系统目录创建一个排除谓词
            for directory in systemAppDirectories {
                let dirExclusionPredicate = NSPredicate(format: "NOT (kMDItemPath BEGINSWITH %@)", directory)
                nonSystemAppPredicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: [appBasePredicate, dirExclusionPredicate]))
            }
            
            // 合并所有非系统应用谓词
            let nonSystemAppPredicate: NSPredicate
            if nonSystemAppPredicates.count > 1 {
                nonSystemAppPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: nonSystemAppPredicates)
            } else if nonSystemAppPredicates.count == 1 {
                nonSystemAppPredicate = nonSystemAppPredicates[0]
            } else {
                nonSystemAppPredicate = NSPredicate(value: false)
            }
            
            // 合并非应用文件和非系统应用的谓词
            metadataQuery.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [nonAppFilePredicate, nonSystemAppPredicate])
            
            // 使用自定义通知来处理文件搜索结果
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: metadataQuery)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFileQueryResults),
                name: .NSMetadataQueryDidFinishGathering,
                object: metadataQuery
            )
            
            metadataQuery.start()
        }
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
                    subtitle: path,
                    lastUsedDate: lastUsedDate,
                    relevanceScore: relevanceScore
                )
                applications.append(result)
            } else if path.contains("Shortcuts") {
                // 简化的快捷指令检测，实际应用中应更精确
                let relevanceScore = calculateRelevanceScore(appName: cleanDisplayName, query: searchQueryText)
                
                let result = SearchResult(
                    id: UUID(),
                    name: cleanDisplayName,
                    path: path,
                    type: .shortcut,
                    category: shortcutsCategory,
                    icon: icon,
                    subtitle: "快捷指令",
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
        var nonSystemApps: [SearchResult] = []
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
            
            // 区分非系统应用和普通文件
            if path.hasSuffix(".app") && !isInSystemDirectory(path) {
                let relevanceScore = calculateRelevanceScore(appName: cleanDisplayName, query: searchQueryText)
                
                let result = SearchResult(
                    id: UUID(),
                    name: cleanDisplayName,
                    path: path,
                    type: .application,
                    category: "其他应用程序",
                    icon: icon,
                    subtitle: path,
                    lastUsedDate: lastUsedDate,
                    relevanceScore: relevanceScore
                )
                nonSystemApps.append(result)
                processedItemCount += 1
            } else {
                let relevanceScore = calculateRelevanceScore(appName: cleanDisplayName, query: searchQueryText)
                
                let result = SearchResult(
                    id: UUID(),
                    name: cleanDisplayName,
                    path: path,
                    type: .file,
                    category: recentFilesCategory,
                    icon: icon,
                    subtitle: path,
                    lastUsedDate: lastUsedDate,
                    relevanceScore: relevanceScore
                )
                files.append(result)
                processedItemCount += 1
            }
        }
        
        // 对非系统应用进行两级排序
        nonSystemApps.sort { (result1, result2) in
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
        
        // 合并所有结果，先显示非系统应用，再显示文件
        let allResults = nonSystemApps + files
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fileSearchResults = allResults
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
    
    func openResult(_ result: SearchResult) {
        NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
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