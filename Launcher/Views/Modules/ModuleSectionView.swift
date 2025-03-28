import SwiftUI

// 模块部分视图 - 显示一个模块的标题和所有项
struct ModuleSectionView: View {
    let section: ModuleSection
    let selectedIndex: SelectableItemIndex?
    let onSelectItem: (SelectableItemIndex) -> Void
    let onExpandHeader: ((ModuleType) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 模块标题
            Text(section.title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            
            // 模块项
            if section.items.isEmpty {
                // 如果没有项，不显示内容
                EmptyView()
            } else {
                ForEach(0..<section.items.count, id: \.self) { index in
                    moduleItemView(at: index)
                }
            }
        }
    }
    
    // 为不同类型的项创建相应的视图
    @ViewBuilder
    private func moduleItemView(at index: Int) -> some View {
        let item = section.items[index]
        let isSelected = selectedIndex == SelectableItemIndex(
            moduleType: section.type,
            itemIndex: index,
            isHeader: index == 0 && (section.type == .ai || section.type == .file)
        )
        let isHeader = index == 0 && (section.type == .ai || section.type == .file)
        
        // 根据具体类型创建不同的视图
        Group {
            if let aiItem = item as? AIQueryItem {
                createItemView(aiItem, isSelected: isSelected, isHeader: isHeader, index: index)
            } else if let appItem = item as? ApplicationItem {
                createItemView(appItem, isSelected: isSelected, isHeader: isHeader, index: index)
            } else if let fileItem = item as? FileItem {
                createItemView(fileItem, isSelected: isSelected, isHeader: isHeader, index: index)
            } else if let fileSearchItem = item as? FileSearchItem {
                createItemView(fileSearchItem, isSelected: isSelected, isHeader: isHeader, index: index)
            } else if let calcItem = item as? CalculatorItem {
                calcItem.createView(isSelected: isSelected) {
                    onSelectItem(SelectableItemIndex(
                        moduleType: section.type,
                        itemIndex: index,
                        isHeader: false
                    ))
                }
            }
        }
    }
    
    // 针对具体类型的视图创建函数
    private func createItemView<T: SelectableItem>(_ item: T, isSelected: Bool, isHeader: Bool, index: Int) -> some View {
        // 特殊处理第一个项(用于AI和文件模块的展开/折叠)
        if isHeader {
            // 对于AI和文件模块的第一个项(查询项)，添加展开/折叠功能
            SelectableItemView(
                item: item,
                isSelected: isSelected,
                showExpand: true,
                isExpanded: section.isExpanded,
                isLoading: section.isLoading
            ) {
                if let onExpandHeader = onExpandHeader {
                    onExpandHeader(section.type)
                } else {
                    onSelectItem(SelectableItemIndex(
                        moduleType: section.type,
                        itemIndex: index,
                        isHeader: true
                    ))
                }
            }
        } else {
            // 标准项视图
            SelectableItemView(
                item: item,
                isSelected: isSelected
            ) {
                onSelectItem(SelectableItemIndex(
                    moduleType: section.type,
                    itemIndex: index,
                    isHeader: false
                ))
            }
        }
    }
}

// 用于显示"加载更多"按钮
struct LoadMoreView: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text("加载更多结果...")
                    .foregroundColor(.secondary)
                    .font(.body)
                Spacer()
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
        .cornerRadius(6)
    }
} 