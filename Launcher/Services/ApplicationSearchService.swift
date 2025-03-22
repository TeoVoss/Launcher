import Foundation
import AppKit
import Combine

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

class ApplicationSearchService: BaseSearchService, ObservableObject {
    @Published var appResults: [SearchResult] = []
    
    // 应用信息缓存
    private var allApps: [AppInfo] = []
    private var metadataQuery: NSMetadataQuery?
    
    // 系统应用目录列表
    private let systemAppDirectories = [
        "/Applications",
        "/System/Applications",
        "/System/Library/CoreServices/Finder.app",
        "/System/Library/CoreServices/System Preferences.app",
        "/System/Library/CoreServices/System Settings.app"
    ]
    
    // 类别标识
    private let applicationCategory = "应用程序"
    
    private let excludedApps = ["Launcher"]
    
    // 应用列表缓存
    private var applications: [AppInfo] = []
    
    override init() {
        super.init()
        DispatchQueue.main.async {
            self.loadAllApps()
        }
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
    
    // 加载所有应用信息
    private func loadAllApps() {
        self.setupMetadataQuery()
        
        guard let metadataQuery = self.metadataQuery else {
            return
        }
        
        // 移除现有的观察者
        NotificationCenter.default.removeObserver(self)
        
        // 应用类型谓词
        let appTypePredicate = NSPredicate(format: "kMDItemContentType = 'com.apple.application-bundle'")
        metadataQuery.predicate = appTypePredicate
        
        // 设置完成通知处理
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInitialAppLoad),
            name: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery
        )
        
        metadataQuery.start()
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
                // 不再使用language变量
                
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
    
    @objc private func handleInitialAppLoad(notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else {
            return
        }
        
        query.disableUpdates()
        
        // 清空应用数据
        self.allApps = []
        
        let contentTypeAttr = kMDItemContentType as String
        
        for item in query.results as! [NSMetadataItem] {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { 
                continue 
            }
            
            // 获取内容类型，确认是应用
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
            }
        }
        
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        
        // 设置文件搜索查询
        self.setupMetadataQuery()
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
    
    // 搜索应用程序
    func search(query: String, systemAppsOnly: Bool = true) -> [SearchResult] {
        if query.isEmpty {
            return []
        }
        
        let searchQueryText = query.lowercased()
        
        // 如果应用列表为空，尝试立即加载
        if self.allApps.isEmpty {
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
            return [tempResult]
        }
        
        // 在内存中过滤应用
        let filteredApps = self.allApps
            .filter { systemAppsOnly ? $0.isSystemApp : true }
            .filter { app in
                appMatchesQuery(app: app, query: searchQueryText)
            }
            .map { app -> SearchResult in
                let relevanceScore = calculateAppRelevanceScore(app: app, query: searchQueryText)
                return SearchResult(
                    id: UUID(),
                    name: app.name,
                    path: app.path,
                    type: .application,
                    category: self.applicationCategory,
                    icon: app.icon,
                    subtitle: "",
                    lastUsedDate: app.lastUsedDate,
                    relevanceScore: relevanceScore
                )
            }
        
        // 对结果进行排序
        let sortedApps = sortSearchResults(filteredApps)
        
        // 更新可观察的结果属性
        DispatchQueue.main.async {
            self.appResults = sortedApps
        }
        
        return sortedApps
    }
    
    // 判断应用是否匹配查询
    private func appMatchesQuery(app: AppInfo, query: String) -> Bool {
        // 检查主名称
        if nameMatchesQuery(name: app.name, query: query) {
            return true
        }
        
        // 检查所有本地化名称
        for name in app.localizedNames {
            if nameMatchesQuery(name: name, query: query) {
                return true
            }
        }
        
        return false
    }
    
    // 计算应用相关性分数
    private func calculateAppRelevanceScore(app: AppInfo, query: String) -> Int {
        let score = calculateRelevanceScore(name: app.name, query: query)
        
        // 如果主名称匹配度不高，检查本地化名称
        if score < 70 {
            var highestScore = score
            for name in app.localizedNames {
                let localizedScore = calculateRelevanceScore(name: name, query: query)
                if localizedScore > highestScore {
                    highestScore = localizedScore
                }
            }
            return highestScore
        }
        
        return score
    }
} 