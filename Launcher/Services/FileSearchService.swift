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
        let fileNamePredicates = self.buildSearchPredicates(forQuery: query)
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
            
            let relevanceScore = calculateRelevanceScore(name: displayName, query: searchQueryText)
            
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
        let sortedFiles = sortSearchResults(files)
        
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
    
    // 添加静态方法，支持分页检索文件
    static func searchFiles(query: String, startIndex: Int = 0, limit: Int = 20) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        
        // 创建元数据查询
        let metadataQuery = NSMetadataQuery()
        metadataQuery.searchScopes = [
            NSMetadataQueryLocalComputerScope,
            NSMetadataQueryUserHomeScope
        ]
        
        metadataQuery.valueListAttributes = [
            kMDItemDisplayName as String,
            kMDItemPath as String,
            kMDItemContentType as String,
            kMDItemKind as String,
            kMDItemFSName as String,
            kMDItemLastUsedDate as String
        ]
        
        metadataQuery.sortDescriptors = [NSSortDescriptor(key: kMDItemLastUsedDate as String, ascending: false)]
        
        // 构建文件搜索谓词
        let fileNamePredicates = buildFileSearchPredicates(forQuery: query)
        let nonAppTypePredicate = NSPredicate(format: "kMDItemContentType != 'com.apple.application-bundle'")
        let nonAppFilePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [nonAppTypePredicate, fileNamePredicates])
        
        metadataQuery.predicate = nonAppFilePredicate
        
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
        let _ = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // 最多等待5秒
                let _ = semaphore.wait(timeout: .now() + 5.0)
                continuation.resume()
            }
        }
        
        // 移除观察者
        NotificationCenter.default.removeObserver(observer)
        metadataQuery.stop()
        
        // 处理分页结果
        var files: [SearchResult] = []
        let recentFilesCategory = "最近文件"
        let maxIndex = min(startIndex + limit, results.count)
        
        // 确保索引在有效范围内
        if startIndex < results.count {
            for i in startIndex..<maxIndex {
                let item = results[i]
                guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
                
                // 获取文件名称
                let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
                
                let icon = NSWorkspace.shared.icon(forFile: path)
                let lastUsedDate = item.value(forAttribute: kMDItemLastUsedDate as String) as? Date
                
                let relevanceScore = calculateFileRelevanceScore(name: displayName, query: query)
                
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
                
                let result = SearchResult(
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
                files.append(result)
            }
        }
        
        // 对文件进行排序
        return sortFileResults(files)
    }
    
    // 辅助方法 - 构建文件搜索谓词
    static func buildFileSearchPredicates(forQuery query: String) -> NSPredicate {
        let queryWords = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        
        if queryWords.isEmpty {
            return NSPredicate(value: false)
        }
        
        var predicates: [NSPredicate] = []
        
        // 1. 精确匹配 - 名称完全等于查询
        let exactNamePredicate = NSPredicate(format: "kMDItemDisplayName ==[cd] %@", query)
        predicates.append(exactNamePredicate)
        
        // 2. 名称开头匹配
        let nameStartsPredicate = NSPredicate(format: "kMDItemDisplayName BEGINSWITH[cd] %@", query)
        predicates.append(nameStartsPredicate)
        
        // 3. 文件名开头匹配
        let fileNameStartsPredicate = NSPredicate(format: "kMDItemFSName BEGINSWITH[cd] %@", query)
        predicates.append(fileNameStartsPredicate)
        
        // 4. 包含匹配
        let nameContainsPredicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", query)
        predicates.append(nameContainsPredicate)
        
        // 使用OR组合所有谓词
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }
    
    // 辅助方法 - 计算文件相关性分数
    static func calculateFileRelevanceScore(name: String, query: String) -> Int {
        let lowerName = name.lowercased()
        let lowerQuery = query.lowercased()
        
        if lowerName == lowerQuery { return 100 }
        if lowerName.hasPrefix(lowerQuery) { return 80 }
        if lowerName.contains(lowerQuery) { return 60 }
        
        // 检查单词匹配
        let nameWords = lowerName.components(separatedBy: .whitespacesAndNewlines)
        for word in nameWords {
            if word.hasPrefix(lowerQuery) { return 50 }
        }
        
        return 20
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