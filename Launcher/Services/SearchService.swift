import Foundation
import AppKit

class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var categories: [SearchResultCategory] = []
    @Published var fileSearchResults: [SearchResult] = []
    
    private let applicationCategory = "应用程序"
    private let shortcutsCategory = "快捷指令"
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
            let shortcutsPredicate = NSPredicate(format: "(kMDItemDisplayName CONTAINS[cd] %@) AND (kMDItemPath CONTAINS[cd] 'Shortcuts')", query)
            metadataQuery.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [appPredicate, shortcutsPredicate])
            
            metadataQuery.start()
        }
    }
    
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
            
            let filePredicate = NSPredicate(format: "(kMDItemDisplayName CONTAINS[cd] %@) AND (kMDItemContentType != 'com.apple.application-bundle')", query)
            metadataQuery.predicate = filePredicate
            
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
            } else if path.contains("Shortcuts") {
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
        
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryResults),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
    }
    
    @objc private func handleFileQueryResults(notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        
        query.disableUpdates()
        
        var files: [SearchResult] = []
        var processedFileCount = 0
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            
            if path.hasSuffix(".app") { continue }
            
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            let icon = NSWorkspace.shared.icon(forFile: path)
            
            if processedFileCount < maxRecentFiles {
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
                processedFileCount += 1
            } else {
                break
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fileSearchResults = files
        }
        
        query.enableUpdates()
        
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