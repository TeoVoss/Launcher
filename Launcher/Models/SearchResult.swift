import Foundation
import AppKit

struct SearchResult: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let type: SearchResultType
    let category: String
    let icon: NSImage
    let subtitle: String
    
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
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .calculator: return 0
        case .application: return 1
        case .system: return 2
        case .document: return 3
        case .file: return 4
        case .folder: return 5
        case .suggestion: return 6
        case .ai: return 7
        }
    }
} 