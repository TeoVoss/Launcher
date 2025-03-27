import SwiftUI

// 可选择项的基础协议
protocol SelectableItem: Identifiable {
    var id: UUID { get }
    var displayName: String { get }
    var subtitle: String { get }
    var iconImage: NSImage { get }
    var type: ItemType { get }
}

// 项目类型枚举
enum ItemType {
    case ai
    case application
    case shortcut
    case file
    case fileSearch
    case calculator
    case webSearch
    
    var categoryTitle: String {
        switch self {
        case .ai: return "AI"
        case .application: return "应用程序"
        case .shortcut: return "快捷指令"
        case .file: return "文件"
        case .fileSearch: return "文件搜索"
        case .calculator: return "计算器"
        case .webSearch: return "网页"
        }
    }
    
    var systemImage: String {
        switch self {
        case .ai: return "brain.fill"
        case .application: return "app.fill"
        case .shortcut: return "shortcut.fill"
        case .file: return "doc.fill"
        case .fileSearch: return "magnifyingglass.circle.fill"
        case .calculator: return "equal.circle.fill"
        case .webSearch: return "globe"
        }
    }
}

// 基础的可选择项视图
struct SelectableItemView<Item: SelectableItem>: View {
    let item: Item
    let isSelected: Bool
    let showExpand: Bool
    let isExpanded: Bool
    let isLoading: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    init(
        item: Item,
        isSelected: Bool,
        showExpand: Bool = false,
        isExpanded: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.showExpand = showExpand
        self.isExpanded = isExpanded
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: item.iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 14))
                    
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 类型标签
                Text(item.type.categoryTitle)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                    )
                    .foregroundColor(Color.gray)
                
                // 展开/加载指示器
                if showExpand {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else if isExpanded {
                        Image(systemName: "chevron.up")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? 
                          Color.accentColor.opacity(0.15) :
                          (isHovered ? Color.gray.opacity(0.08) : Color.clear))
            )
            .overlay(
                isSelected ?
                    RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    : nil
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            isHovered = hover
        }
    }
} 
