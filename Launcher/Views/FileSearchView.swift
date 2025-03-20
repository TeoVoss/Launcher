import SwiftUI
import AppKit

// 文件搜索视图
struct FileSearchView: View {
    @ObservedObject var searchService: SearchService
    @Binding var searchText: String
    @Binding var selectedIndex: Int?
    var onResultSelected: (SearchResult) -> Void
    var onResultsChanged: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if searchService.fileSearchResults.isEmpty {
                // 使用ScrollView保持布局结构一致，避免从无结果到有结果时的布局跳变
                ScrollView {
                    VStack {
                        Text(searchText.isEmpty ? "请输入搜索关键词" : "无匹配文件")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 16)
                    }
                    .frame(minHeight: 120) // 设置最小高度，避免内容过于居中
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(searchService.fileSearchResults.enumerated()), id: \.element.id) { index, result in
                                ResultRow(result: result, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        onResultSelected(result)
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                        .onChange(of: selectedIndex) { _, newIndex in
                            if let index = newIndex {
                                withAnimation {
                                    proxy.scrollTo(index, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchService.searchFiles(query: newValue)
            selectedIndex = searchService.fileSearchResults.isEmpty ? nil : 0
            // 通知主视图文件搜索结果已更新
            onResultsChanged()
        }
        .onAppear {
            searchService.searchFiles(query: searchText)
            selectedIndex = searchService.fileSearchResults.isEmpty ? nil : 0
            // 通知主视图文件搜索结果已更新
            onResultsChanged()
        }
        .onChange(of: searchService.fileSearchResults) { _, _ in
            // 监听文件搜索结果变化，通知主视图调整高度
            onResultsChanged()
        }
    }
} 