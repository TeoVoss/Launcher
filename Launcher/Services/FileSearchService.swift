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
} 