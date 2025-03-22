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
    @State private var contentHeight: CGFloat = 0
    
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
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                    }
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: FileContentHeightPreferenceKey.self,
                            value: geo.size.height
                        )
                    })
                }
                .frame(maxHeight: 300)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(searchService.fileSearchResults.enumerated()), id: \.element.id) { index, result in
                                    ResultRowView(result: result, isSelected: selectedIndex == index)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedIndex = index
                                            onResultSelected(result)
                                        }
                                }
                            }
                            .onChange(of: selectedIndex) { newIndex in
                                if let index = newIndex {
                                    withAnimation {
                                        proxy.scrollTo(index, anchor: .center)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: FileContentHeightPreferenceKey.self,
                                value: geo.size.height
                            )
                        })
                    }
                    .frame(maxHeight: 300)
                    // 添加onAppear处理，确保显示时滚动到顶部并选中第一项
                    .onAppear {
                        if !searchService.fileSearchResults.isEmpty && selectedIndex == nil {
                            DispatchQueue.main.async {
                                selectedIndex = 0
                                proxy.scrollTo(0, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .onPreferenceChange(FileContentHeightPreferenceKey.self) { height in
            contentHeight = height
            onResultsChanged()
        }
        .onChange(of: searchService.fileSearchResults) { newResults in
            // 当结果变化时，如果有结果但没有选中项，则选中第一项
            if !newResults.isEmpty && selectedIndex == nil {
                selectedIndex = 0
            }
            onResultsChanged()
        }
        // 视图消失时清理状态
        .onDisappear {
            print("文件搜索视图消失")
            
            // 确保在离开视图时清空结果和状态，避免状态跟随到其他视图
            // 不应依赖于外部ViewModel来清理这个状态，应在本视图负责自己的清理
            selectedIndex = nil
            
            // 注意：这里不清空fileSearchResults，而是让ViewModel的exitCurrentMode方法负责清理
            // 这是因为fileSearchResults可能被其他组件需要访问，需由ViewModel统一管理
        }
    }
} 
