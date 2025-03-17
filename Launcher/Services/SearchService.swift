import Foundation
import AppKit

class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    
    private let applicationCategory = "应用程序"
    private let recentFilesCategory = "最近文件"
    private let maxRecentFiles = 10
    private var metadataQuery: NSMetadataQuery?
    
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
            
            let appPredicate = NSPredicate(format: "(kMDItemDisplayName CONTAINS[cd] %@) AND (kMDItemContentType = 'com.apple.application-bundle')", query)
            let filePredicate = NSPredicate(format: "(kMDItemDisplayName CONTAINS[cd] %@) AND (kMDItemContentType != 'com.apple.application-bundle')", query)
            metadataQuery.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [appPredicate, filePredicate])
            
            metadataQuery.start()
        }
    }
    
    @objc private func handleQueryResults(notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        
        query.disableUpdates()
        
        var applications: [SearchResult] = []
        var recentFiles: [SearchResult] = []
        var processedFileCount = 0
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            let icon = NSWorkspace.shared.icon(forFile: path)
            
            if path.hasSuffix(".app") {
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
            } else if processedFileCount < maxRecentFiles {
                let result = SearchResult(
                    id: UUID(),
                    name: displayName,
                    path: path,
                    type: .file,
                    category: recentFilesCategory,
                    icon: icon,
                    subtitle: path
                )
                recentFiles.append(result)
                processedFileCount += 1
            } else if !applications.isEmpty {
                break
            }
        }
        
        let allResults = applications + recentFiles
        
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
            if !recentFiles.isEmpty {
                categories.append(SearchResultCategory(
                    id: self.recentFilesCategory,
                    title: self.recentFilesCategory,
                    results: recentFiles
                ))
            }
            
            self.categories = categories
        }
        
        query.enableUpdates()
    }
    
    func openResult(_ result: SearchResult) {
        NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
    }
    
    func clearResults() {
        DispatchQueue.main.async {
            self.searchResults = []
            self.categories = []
        }
    }
} 