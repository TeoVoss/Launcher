import SwiftUI
import AppKit

// 模块类型枚举
enum ModuleType: Int, CaseIterable {
    case ai = 0
    case application = 1
    case file = 2
    case calculator = 3
    case webSearch = 4
    
    var title: String {
        switch self {
        case .ai: return "AI"
        case .application: return "应用"
        case .file: return "文件"
        case .calculator: return "计算器"
        case .webSearch: return "网页"
        }
    }
    
    var systemImage: String {
        switch self {
        case .ai: return "brain.fill"
        case .application: return "app.fill"
        case .file: return "doc.fill"
        case .calculator: return "equal.circle.fill"
        case .webSearch: return "globe"
        }
    }
}

// AI 查询项
struct AIQueryItem: SelectableItem {
    let id = UUID()
    let query: String
    var displayName: String { return "问：\(query)" }
    var subtitle: String { return "" }
    var iconImage: NSImage { 
        return NSImage(systemSymbolName: "brain.fill", accessibilityDescription: nil) ?? NSImage() 
    }
    var type: ItemType { return .ai }
}

// 应用项 - 基于现有的 SearchResult
struct ApplicationItem: SelectableItem {
    let searchResult: SearchResult
    
    var id: UUID { return searchResult.id }
    var displayName: String { return searchResult.name }
    var subtitle: String { return searchResult.subtitle }
    var iconImage: NSImage { return searchResult.icon }
    var type: ItemType { return .application }
    var path: String { return searchResult.path }
}

// 文件搜索项
struct FileSearchItem: SelectableItem {
    let id = UUID()
    let query: String
    var displayName: String { return "搜索：\(query)" }
    var subtitle: String { return "" }
    var iconImage: NSImage { 
        return NSImage(systemSymbolName: "magnifyingglass.circle.fill", accessibilityDescription: nil) ?? NSImage() 
    }
    var type: ItemType { return .fileSearch }
}

// 文件项 - 基于现有的 SearchResult
struct FileItem: SelectableItem {
    let searchResult: SearchResult
    
    var id: UUID { return searchResult.id }
    var displayName: String { return searchResult.name }
    var subtitle: String { return searchResult.subtitle }
    var iconImage: NSImage { return searchResult.icon }
    var type: ItemType { return .file }
    var path: String { return searchResult.path }
}

// AI 回复内容项
struct AIResponseItem: SelectableItem {
    let id = UUID()
    let content: String
    var displayName: String { return "AI回复" }
    var subtitle: String { return content.isEmpty ? "生成中..." : String(content.prefix(60)) }
    var iconImage: NSImage { 
        return NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil) ?? NSImage() 
    }
    var type: ItemType { return .ai }
}

// 计算器项
struct CalculatorItem: SelectableItem {
    let id = UUID()
    let formula: String
    let result: String
    
    var displayName: String { return formula }
    var subtitle: String { return result }
    var iconImage: NSImage {
        return NSImage(systemSymbolName: "equal.circle.fill", accessibilityDescription: nil) ?? NSImage()
    }
    var type: ItemType { return .calculator }
}

// 模块部分（每个模块的标题和项列表）
struct ModuleSection {
    let type: ModuleType
    let title: String
    var items: [any SelectableItem]
    var isExpanded: Bool = false
    var isLoading: Bool = false
    
    init(type: ModuleType, items: [any SelectableItem] = [], isExpanded: Bool = false, isLoading: Bool = false) {
        self.type = type
        self.title = type.title
        self.items = items
        self.isExpanded = isExpanded
        self.isLoading = isLoading
    }
}

// 可选择项的索引标识
struct SelectableItemIndex: Equatable {
    let moduleType: ModuleType
    let itemIndex: Int
    let isHeader: Bool
    
    static func == (lhs: SelectableItemIndex, rhs: SelectableItemIndex) -> Bool {
        return lhs.moduleType == rhs.moduleType && 
               lhs.itemIndex == rhs.itemIndex &&
               lhs.isHeader == rhs.isHeader
    }
}

// 将 SearchResult 转换为相应的 SelectableItem
extension SearchResult {
    func toSelectableItem() -> any SelectableItem {
        switch self.type {
        case .application, .shortcut:
            return ApplicationItem(searchResult: self)
        case .file, .folder, .document:
            return FileItem(searchResult: self)
        default:
            // 其他类型可以在此处添加相应的处理
            return ApplicationItem(searchResult: self)
        }
    }
} 