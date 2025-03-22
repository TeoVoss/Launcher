import Foundation
import AppKit
import SwiftUI

struct SearchResult: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let type: SearchResultType
    let category: String
    let icon: NSImage
    let subtitle: String
    let lastUsedDate: Date?
    let relevanceScore: Int
    
    init(id: UUID, name: String, path: String, type: SearchResultType, category: String, icon: NSImage, subtitle: String, lastUsedDate: Date? = nil, relevanceScore: Int = 0) {
        self.id = id
        self.name = name
        self.path = path
        self.type = type
        self.category = category
        self.icon = icon
        self.subtitle = subtitle
        self.lastUsedDate = lastUsedDate
        self.relevanceScore = relevanceScore
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

enum SearchResultType {
    case application
    case file
    case ai
    case folder
    case document
    case system
    case calculator
    case suggestion
    case shortcut
    
    var systemImage: String {
        switch self {
        case .calculator: return "equal.circle.fill"
        case .application: return "app.fill"
        case .file: return "doc.fill"
        case .folder: return "folder.fill"
        case .document: return "doc.text.fill"
        case .system: return "gearshape.fill"
        case .suggestion: return "magnifyingglass"
        case .ai: return "brain.fill"
        case .shortcut: return "command.square.fill"
        }
    }
}

struct SearchResultCategory: Identifiable {
    let id: String
    let title: String
    let results: [SearchResult]
    
    static func categorize(_ results: [SearchResult]) -> [SearchResultCategory] {
        let groupedResults = Dictionary(grouping: results) { $0.category }
        return groupedResults.map { (key, value) in
            SearchResultCategory(id: key, title: key, results: value)
        }.sorted { $0.title < $1.title }
    }
}

// 扩展 SearchResultType 以支持分类标题和排序
extension SearchResultType {
    var categoryTitle: String {
        switch self {
        case .application: return "应用程序"
        case .file: return "文件"
        case .folder: return "文件夹"
        case .document: return "文档"
        case .system: return "系统偏好设置"
        case .calculator: return "计算器"
        case .suggestion: return "建议"
        case .ai: return "AI"
        case .shortcut: return "快捷指令"
        }
    }
    
    var categoryColor: Color {
        switch self {
        case .application: return Color.blue
        case .file: return Color.green
        case .folder: return Color.orange
        case .document: return Color.purple
        case .system: return Color.gray
        case .calculator: return Color.pink
        case .suggestion: return Color.teal
        case .ai: return Color.red
        case .shortcut: return Color.indigo
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .calculator: return 0
        case .application: return 1
        case .system: return 2
        case .shortcut: return 3
        case .document: return 4
        case .file: return 5
        case .folder: return 6
        case .suggestion: return 7
        case .ai: return 8
        }
    }
} 