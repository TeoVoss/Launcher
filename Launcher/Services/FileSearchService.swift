import Foundation
import AppKit
import Combine

class FileSearchService: BaseSearchService, ObservableObject {
    @Published var fileResults: [SearchResult] = []
    
    private var metadataQuery: NSMetadataQuery?
    private let maxRecentFiles = 20
    private let recentFilesCategory = "最近文件"
    
    override init() {
        super.init()
        setupMetadataQuery()
    }
    
    deinit {
        cleanup()
    }
    
    private func cleanup() {
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
        
        self.metadataQuery = query
    }
    
    // 搜索文件
    func search(query: String) {
        guard !query.isEmpty else {
            DispatchQueue.main.async {
                self.fileResults = []
            }
            return
        }
        
        guard let metadataQuery = self.metadataQuery else {
            return
        }
        
        // 构建文件搜索谓词
        let fileNamePredicates = BaseSearchService.buildSearchPredicates(forQuery: query)
        let nonAppTypePredicate = NSPredicate(format: "kMDItemContentType != 'com.apple.application-bundle'")
        let nonAppFilePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [nonAppTypePredicate, fileNamePredicates])
        
        metadataQuery.predicate = nonAppFilePredicate
        
        // 移除现有的观察者
        NotificationCenter.default.removeObserver(self)
        
        // 使用自定义通知来处理文件搜索结果
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleFileQueryResults),
            name: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery
        )
        
        metadataQuery.start()
    }
    
    // 处理文件搜索结果
    @objc private func handleFileQueryResults(notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        
        query.disableUpdates()
        
        var files: [SearchResult] = []
        var processedItemCount = 0
        let searchQueryText = query.predicate?.description.components(separatedBy: "\"").filter { !$0.contains("kMDItem") }.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String,
                  processedItemCount < maxRecentFiles else { break }
            
            // 获取文件名称
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            
            let icon = NSWorkspace.shared.icon(forFile: path)
            let lastUsedDate = item.value(forAttribute: kMDItemLastUsedDate as String) as? Date
            
            let relevanceScore = BaseSearchService.calculateRelevanceScore(name: displayName, query: searchQueryText)
            
            // 确定文件类型
            let fileType: SearchResultType
            if path.hasSuffix(".app") {
                fileType = .application
            } else if isDirectory(path: path) {
                fileType = .folder
            } else if isDocumentFile(path: path) {
                fileType = .document
            } else {
                fileType = .file
            }
            
            let result = SearchResult(
                id: UUID(),
                name: displayName,
                path: path,
                type: fileType,
                category: recentFilesCategory,
                icon: icon,
                subtitle: "",
                lastUsedDate: lastUsedDate,
                relevanceScore: relevanceScore
            )
            files.append(result)
            processedItemCount += 1
        }
        
        // 对文件进行排序
        let sortedFiles = BaseSearchService.sortSearchResults(files)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fileResults = sortedFiles
        }
        
        query.enableUpdates()
        
        // 恢复原始查询结果处理器
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFileQueryResults),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
    }
    
    // 判断路径是否是目录
    private func isDirectory(path: String) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }
    
    // 判断文件是否是文档类型
    private func isDocumentFile(path: String) -> Bool {
        let documentExtensions = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "pages", "numbers", "key", "md"]
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return documentExtensions.contains(fileExtension)
    }
    
    // 优化静态搜索方法，支持高效的分页搜索
    static func searchFiles(query: String, startIndex: Int = 0, limit: Int = 20) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        
        // 使用共享缓存实例
        return await withCheckedContinuation { continuation in
            Task {
                // 创建元数据查询
                let metadataQuery = NSMetadataQuery()
                metadataQuery.searchScopes = [
                    NSMetadataQueryLocalComputerScope,
                    NSMetadataQueryUserHomeScope
                ]
                
                // 只获取必要的属性，减少内存占用
                metadataQuery.valueListAttributes = [
                    kMDItemDisplayName as String,
                    kMDItemPath as String,
                    kMDItemContentType as String,
                    kMDItemLastUsedDate as String
                ]
                
                // 按最近使用日期排序
                metadataQuery.sortDescriptors = [NSSortDescriptor(key: kMDItemLastUsedDate as String, ascending: false)]
                
                // 构建文件搜索谓词
                let fileNamePredicates = BaseSearchService.buildSearchPredicates(forQuery: query)
                let nonAppTypePredicate = NSPredicate(format: "kMDItemContentType != 'com.apple.application-bundle'")
                let nonAppFilePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [nonAppTypePredicate, fileNamePredicates])
                
                metadataQuery.predicate = nonAppFilePredicate
                
                // 设置结果限制，减少内存使用和提高性能
                // 注意: 我们请求比需要的更多结果，以确保有足够的数据用于分页
                metadataQuery.notificationBatchingInterval = 0.1
                
                // 创建用于等待查询完成的信号量
                let semaphore = DispatchSemaphore(value: 0)
                var results: [NSMetadataItem] = []
                
                // 设置通知监听
                let observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: metadataQuery,
                    queue: .main
                ) { notification in
                    guard let query = notification.object as? NSMetadataQuery else { return }
                    query.disableUpdates()
                    results = query.results as! [NSMetadataItem]
                    semaphore.signal()
                }
                
                // 开始查询
                metadataQuery.start()
                
                // 等待查询完成或超时
                let _ = semaphore.wait(timeout: .now() + 3.0) // 最多等待3秒
                
                // 移除观察者和停止查询
                NotificationCenter.default.removeObserver(observer)
                metadataQuery.stop()
                
                // 处理分页结果
                var files: [SearchResult] = []
                let recentFilesCategory = "最近文件"
                var maxIndex = min(startIndex + limit, results.count)
                
                // 防止越界
                let validStartIndex = min(startIndex, results.count)
                maxIndex = min(validStartIndex + limit, results.count)
                
                // 确保索引在有效范围内
                if validStartIndex < results.count {
                    // 并行处理结果，提高性能
                    await withTaskGroup(of: SearchResult?.self) { group in
                        for i in validStartIndex..<maxIndex {
                            group.addTask {
                                let item = results[i]
                                guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { return nil }
                                
                                // 获取文件名称
                                let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
                                
                                // 异步获取图标
                                let icon = NSWorkspace.shared.icon(forFile: path)
                                let lastUsedDate = item.value(forAttribute: kMDItemLastUsedDate as String) as? Date
                                
                                let relevanceScore = BaseSearchService.calculateRelevanceScore(name: displayName, query: query)
                                
                                // 确定文件类型
                                let fileType: SearchResultType
                                if path.hasSuffix(".app") {
                                    fileType = .application
                                } else if isDirectoryPath(path: path) {
                                    fileType = .folder
                                } else if isDocumentFilePath(path: path) {
                                    fileType = .document
                                } else {
                                    fileType = .file
                                }
                                
                                return SearchResult(
                                    id: UUID(),
                                    name: displayName,
                                    path: path,
                                    type: fileType,
                                    category: recentFilesCategory,
                                    icon: icon,
                                    subtitle: path,
                                    lastUsedDate: lastUsedDate,
                                    relevanceScore: relevanceScore
                                )
                            }
                        }
                        
                        // 收集任务组的结果
                        for await result in group {
                            if let result = result {
                                files.append(result)
                            }
                        }
                    }
                    
                    // 对文件进行排序
                    files = sortFileResults(files)
                }
                
                continuation.resume(returning: files)
            }
        }
    }
    
    // 辅助方法 - 计算文件相关性分数
    static func calculateFileRelevanceScore(name: String, query: String) -> Int {
        // 直接使用基类的静态方法
        return BaseSearchService.calculateRelevanceScore(name: name, query: query)
    }
    
    // 辅助方法 - 判断路径是否为目录
    static func isDirectoryPath(path: String) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        return false
    }
    
    // 辅助方法 - 判断路径是否为文档文件
    static func isDocumentFilePath(path: String) -> Bool {
        let documentExtensions = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md"]
        let fileExtension = (path as NSString).pathExtension.lowercased()
        return documentExtensions.contains(fileExtension)
    }
    
    // 辅助方法 - 文件结果排序
    static func sortFileResults(_ results: [SearchResult]) -> [SearchResult] {
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
} 