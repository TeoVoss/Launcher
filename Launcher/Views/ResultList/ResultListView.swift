import SwiftUI

struct ResultListView: View {
    let results: [SearchResult]
    @Binding var selectedIndex: Int?
    var onItemClick: (SearchResult) -> Void
    
    // 统一滚动逻辑标识符
    private var scrollId: String {
        "results-\(results.count)"
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        ResultRowView(
                            result: result,
                            isSelected: selectedIndex == index
                        )
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                            onItemClick(result)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
            // 监听选中索引变化，滚动到选中项
            .onChange(of: selectedIndex) { newIndex in
                if let index = newIndex, results.indices.contains(index) {
                    print("滚动到选中项: \(index)")
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
            // 在视图出现时处理滚动
            .onAppear {
                print("结果列表视图显示 - 结果数量: \(results.count)")
                
                // 确保滚动到顶部
                if results.indices.contains(0) {
                    print("滚动到列表顶部")
                    proxy.scrollTo(0, anchor: .top)
                }
                
                // 默认选中第一项（如果没有选中项且有结果）
                if selectedIndex == nil && !results.isEmpty {
                    print("默认选中第一项")
                    DispatchQueue.main.async {
                        selectedIndex = 0
                    }
                }
            }
            // 使用结果集的唯一标识确保视图正确刷新
            .id(scrollId)
        }
        .background(GeometryReader { geo in
            Color.clear.onAppear {
                print("结果列表实际高度: \(geo.size.height)")
            }
        })
    }
} 