import Foundation
import AppKit
import Combine

class ShortcutSearchService: BaseSearchService, ObservableObject {
    @Published var shortcutResults: [SearchResult] = []
    
    // 快捷指令信息缓存
    private var allShortcuts: [AppInfo] = []
    
    // 类别标识
    private let shortcutsCategory = "快捷指令"
    
    // 快捷指令存储目录
    private let shortcutDirectories = [
        "~/Library/Shortcuts",
        "/private/var/mobile/Library/Shortcuts"
    ]
    
    override init() {
        super.init()
        DispatchQueue.main.async {
            self.loadShortcuts()
        }
    }
    
    // 加载快捷指令
    private func loadShortcuts() {
        loadShortcutsUsingCLI()
    }
    
    // 使用CLI命令获取快捷指令列表
    private func loadShortcutsUsingCLI() {
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
                try task.run()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    if output.isEmpty {
                        // 命令未返回任何快捷指令
                        return
                    } else {
                        // 解析输出，格式通常为每行一个快捷指令名
                        let shortcuts = parseShortcutsOutput(output)
                        
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
                                lastUsedDate: nil
                            )
                            self.allShortcuts.append(appInfo)
                        }
                    }
                }
            } catch {
                // 执行命令失败
            }
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
                return icon
            }
        }
        
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
    
    // 搜索快捷指令
    func search(query: String) -> [SearchResult] {
        if query.isEmpty {
            return []
        }
        
        let searchQueryText = query.lowercased()
        
        // 如果快捷指令列表为空，尝试立即加载
        if self.allShortcuts.isEmpty {
            self.loadShortcuts()
            return []
        }
        
        // 在内存中过滤快捷指令
        let filteredShortcuts = self.allShortcuts
            .filter { app in
                BaseSearchService.nameMatchesQuery(name: app.name, query: searchQueryText)
            }
            .map { app -> SearchResult in
                let relevanceScore = BaseSearchService.calculateRelevanceScore(name: app.name, query: searchQueryText)
                return SearchResult(
                    id: UUID(),
                    name: app.name,
                    path: app.path,
                    type: .shortcut,
                    category: self.shortcutsCategory,
                    icon: app.icon,
                    subtitle: "",
                    lastUsedDate: app.lastUsedDate,
                    relevanceScore: relevanceScore
                )
            }
        
        // 对结果进行排序
        let sortedShortcuts = BaseSearchService.sortSearchResults(filteredShortcuts)
        
        // 更新可观察的结果属性
        DispatchQueue.main.async {
            self.shortcutResults = sortedShortcuts
        }
        
        return sortedShortcuts
    }
    
    // 执行快捷指令
    func runShortcut(_ result: SearchResult) {
        if result.type != .shortcut || !result.path.hasPrefix("shortcuts run") {
            return
        }
        
        // 解析命令字符串
        let components = result.path.components(separatedBy: " ")
        if components.count < 3 || components[0] != "shortcuts" || components[1] != "run" {
            return
        }
        
        // 重建快捷指令名称（可能包含空格）
        let shortcutName = components[2...].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["run", shortcutName]
        
        // 设置可执行文件路径
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        
        do {
            try task.run()
        } catch {
            // 处理错误
        }
    }
} 