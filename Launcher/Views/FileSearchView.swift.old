import SwiftUI
import AppKit

// 为高度偏好定义一个新的PreferenceKey
struct FileContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// 文件搜索视图
struct FileSearchView: View {
    @ObservedObject var searchService: SearchService
    @Binding var searchText: String
    @Binding var selectedIndex: Int?
    
    var onResultSelected: (SearchResult) -> Void
    var onResultsChanged: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if searchService.isSearchingFiles {
                // 搜索中显示进度指示器
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("正在搜索文件...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
            } else if searchService.fileSearchResults.isEmpty {
                // 没有结果时显示提示
                Text("未找到匹配的文件")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                // 显示搜索结果
                VStack(spacing: 0) {
                    ForEach(Array(searchService.fileSearchResults.enumerated()), id: \.element.id) { index, result in
                        ResultRowView(
                            result: result,
                            isSelected: index == selectedIndex
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                            onResultSelected(result)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 50, maxHeight: 250)
        .onAppear {
            searchService.searchFiles(query: searchText)
        }
        .onChange(of: searchService.fileSearchResults, perform: { newResults in
            onResultsChanged()
            
            // 如果有结果，自动选择第一个
            if !newResults.isEmpty && selectedIndex == nil {
                selectedIndex = 0
            }
        })
        .onChange(of: searchText, perform: { newValue in
            // 当搜索文本变化时，执行文件搜索
            if !newValue.isEmpty {
                searchService.searchFiles(query: newValue)
            }
        })
    }
} 
