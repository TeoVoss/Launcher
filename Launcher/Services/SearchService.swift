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
            
            // 搜索应用程序
            let appPredicate = NSPredicate(format: "(kMDItemDisplayName CONTAINS[cd] %@) AND (kMDItemContentType = 'com.apple.application-bundle')", query)
            
            // 添加快捷指令搜索（演示用）
            let shortcutsPredicate = NSPredicate(format: "(kMDItemDisplayName CONTAINS[cd] %@) AND (kMDItemPath CONTAINS[cd] 'Shortcuts')", query)
            
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
            
            // 文件搜索
            let nonAppFilePredicate = NSPredicate(format: "(kMDItemDisplayName CONTAINS[cd] %@) AND (kMDItemContentType != 'com.apple.application-bundle')", query)
            
            // 搜索不在系统目录列表中的应用程序
            var nonSystemAppPredicates: [NSPredicate] = []
            let appTypePredicate = NSPredicate(format: "kMDItemContentType = 'com.apple.application-bundle'")
            let displayNamePredicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", query)
            
            // 组合应用类型和名称匹配谓词
            let appBasePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [appTypePredicate, displayNamePredicate])
            
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
    
    @objc private func handleQueryResults(notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        
        query.disableUpdates()
        
        var applications: [SearchResult] = []
        var shortcuts: [SearchResult] = []
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            let icon = NSWorkspace.shared.icon(forFile: path)
            
            // 检查应用程序是否在系统目录下
            if path.hasSuffix(".app") && isInSystemDirectory(path) {
                let result = SearchResult(
                    id: UUID(),
                    name: displayName,
                    path: path,
                    type: .application,
                    category: applicationCategory,
                    icon: icon,
                    subtitle: path
                )
                applications.append(result)
            } else if path.contains("Shortcuts") {
                // 简化的快捷指令检测，实际应用中应更精确
                let result = SearchResult(
                    id: UUID(),
                    name: displayName,
                    path: path,
                    type: .shortcut,
                    category: shortcutsCategory,
                    icon: icon,
                    subtitle: "快捷指令"
                )
                shortcuts.append(result)
            }
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
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String,
                  processedItemCount < maxRecentFiles else { break }
            
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            let icon = NSWorkspace.shared.icon(forFile: path)
            
            // 区分非系统应用和普通文件
            if path.hasSuffix(".app") && !isInSystemDirectory(path) {
                let result = SearchResult(
                    id: UUID(),
                    name: displayName,
                    path: path,
                    type: .application,
                    category: "其他应用程序",
                    icon: icon,
                    subtitle: path
                )
                nonSystemApps.append(result)
                processedItemCount += 1
            } else {
                let result = SearchResult(
                    id: UUID(),
                    name: displayName,
                    path: path,
                    type: .file,
                    category: recentFilesCategory,
                    icon: icon,
                    subtitle: path
                )
                files.append(result)
                processedItemCount += 1
            }
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
} 