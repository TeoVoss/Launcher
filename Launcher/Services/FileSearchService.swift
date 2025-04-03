import Foundation
import Combine
import AppKit

class FileSearchService: ObservableObject {
    @Published var fileResults: [SearchResult] = []
    @Published var isSearchingFile: Bool = false
    
    // MARK: - 缓存实现
    private struct CacheEntry {
        let results: [SearchResult]
        let timestamp: Date
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let cacheLock = NSLock()
    
    // MARK: - 分页控制
    private let pageSize = 20
    private var currentPage = 0
    private var hasMoreResults = false
    private var currentQuery = ""
    
    // 当前完整查询结果（来自缓存或新查询）
    private var currentFullResults: [SearchResult] = []
    
    // MARK: - 公共接口
    
    /// 发起搜索。如果 loadMore 为 false，则进行全新搜索，否则加载下一页。
    func search(query: String, loadMore: Bool = false) {
        guard !query.isEmpty else {
            return
        }
        
        if !loadMore {
            // 新搜索，重置状态
            self.resetSearchState(for: query)
            // 优先从缓存中取全量结果，再做分页
            if let cached = getCachedResults(for: query) {
                currentFullResults = cached
                appendNextPage(from: cached)
                return
            }
            // 缓存没有则发起新查询
            executeSearch(query: query)
        } else {
            // 加载更多：如果有缓存则直接分页加载
            if let cached = getCachedResults(for: currentQuery) {
                currentFullResults = cached
                appendNextPage(from: cached)
            }
        }
    }
    
    /// 加载下一页数据
    func loadMore() {
        search(query: currentQuery, loadMore: true)
    }
    
    /// 清空当前搜索结果和状态
    func clearResults() {
        resetSearchState(for: "")
    }
    
    /// 清空缓存
    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeAll()
    }
}

// MARK: - 私有实现

private extension FileSearchService {
    
    /// 重置搜索状态
    func resetSearchState(for query: String) {
        currentQuery = query
        currentPage = 0
        hasMoreResults = false
        fileResults = []
        currentFullResults = []
    }
    
    /// 将结果缓存，缓存有效期 5 分钟
    func cacheResults(_ results: [SearchResult], for query: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache[query] = CacheEntry(results: results, timestamp: Date())
    }
    
    /// 从缓存中获取结果
    func getCachedResults(for query: String) -> [SearchResult]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let entry = cache[query], Date().timeIntervalSince(entry.timestamp) < 300 {
            return entry.results
        } else {
            cache[query] = nil
            return nil
        }
    }
    
    /// 使用 NSMetadataQuery 异步执行搜索，获取完整结果后进行缓存和分页加载
    func executeSearch(query: String) {
        isSearchingFile = true
        let metadataQuery = NSMetadataQuery()
        metadataQuery.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
        metadataQuery.valueListAttributes = [
            kMDItemDisplayName,
            kMDItemPath,
            kMDItemContentType,
            kMDItemLastUsedDate
        ].map { $0 as String }
        metadataQuery.sortDescriptors = [
            NSSortDescriptor(key: kMDItemLastUsedDate as String, ascending: false)
        ]
        metadataQuery.predicate = createSearchPredicate(query: query)
        
        // 监听搜索完成通知
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: metadataQuery, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            metadataQuery.disableUpdates()
            let items = metadataQuery.results as? [NSMetadataItem] ?? []
            let fullResults = self.processSearchResults(items: items, query: query)
            isSearchingFile = false
            // 缓存完整结果
            self.cacheResults(fullResults, for: query)
            self.currentFullResults = fullResults
            // 重置分页后加载第一页数据
            self.currentPage = 0
            self.appendNextPage(from: fullResults)
            metadataQuery.stop()
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        metadataQuery.start()
    }
    
    /// 从完整结果中追加下一页数据
    func appendNextPage(from fullResults: [SearchResult]) {
        let start = currentPage * pageSize
        guard start < fullResults.count else { return }
        let end = min(start + pageSize, fullResults.count)
        let pageResults = Array(fullResults[start..<end])
        currentPage += 1
        hasMoreResults = fullResults.count > end
        fileResults.append(contentsOf: pageResults)
    }
    
    /// 构造搜索 predicate，包含关键词匹配和排除应用包
    func createSearchPredicate(query: String) -> NSPredicate {
        let namePredicates = BaseSearchService.buildSearchPredicates(forQuery: query)
        let nonAppPredicate = NSPredicate(format: "kMDItemContentType != 'com.apple.application-bundle'")
        return NSCompoundPredicate(andPredicateWithSubpredicates: [nonAppPredicate, namePredicates])
    }
    
    /// 处理 NSMetadataQuery 返回的结果，生成 SearchResult 数组
    func processSearchResults(items: [NSMetadataItem], query: String) -> [SearchResult] {
        return items.compactMap { item in
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String,
                  let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String else {
                return nil
            }
            let icon = NSWorkspace.shared.icon(forFile: path)
            let lastUsedDate = item.value(forAttribute: kMDItemLastUsedDate as String) as? Date
            let relevanceScore = calculateRelevanceScore(name: displayName, query: query)
            let fileType = determineFileType(path: path)
            return SearchResult(
                id: UUID(),
                name: displayName,
                path: path,
                type: fileType,
                category: "文件",
                icon: icon,
                subtitle: path,
                lastUsedDate: lastUsedDate,
                relevanceScore: relevanceScore
            )
        }
    }
    
    /// 判断文件类型：应用、文件夹、文档或其他文件
    func determineFileType(path: String) -> SearchResultType {
        if path.hasSuffix(".app") {
            return .application
        } else if isDirectory(path: path) {
            return .folder
        } else if isDocumentFile(path: path) {
            return .document
        } else {
            return .file
        }
    }
    
    func isDirectory(path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
    
    func isDocumentFile(path: String) -> Bool {
        let extensions = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md"]
        return extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
    
    /// 根据名称和查询字符串计算相关性得分
    func calculateRelevanceScore(name: String, query: String) -> Int {
        let nameWords = name.components(separatedBy: .whitespacesAndNewlines)
        let queryWords = query.components(separatedBy: .whitespacesAndNewlines)
        var score = 0
        for qWord in queryWords {
            for nWord in nameWords {
                if nWord.lowercased().contains(qWord.lowercased()) {
                    score += qWord.count * 10
                }
            }
        }
        return score
    }
}
