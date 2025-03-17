import SwiftUI

// 创建一个 PreferenceKey 来传递内容高度
struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AIResponseView: View {
    @ObservedObject var aiService: AIService
    let prompt: String
    let onEscape: () -> Void
    // 添加高度变化回调函数
    var onHeightChange: ((CGFloat) -> Void)? = nil
    @State private var contentHeight: CGFloat = 0
    @State private var responseHeight: CGFloat = 0
    @State private var previousPrompt: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 用户问题
            Text(prompt)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geo in
                    Color.clear.preference(
                        key: ContentHeightPreferenceKey.self,
                        value: geo.size.height
                    )
                })
                .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                    contentHeight = height
                    updateTotalHeight()
                }
            
            // AI 回复区域 - 使用一个固定的 ScrollView 结构，避免布局跳变
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        if aiService.currentResponse.isEmpty {
                            // "正在思考中"状态
                            HStack(spacing: 4) {
                                Text("正在思考中...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(height: 16)
                            }
                            .id("loading")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        } else {
                            // 有内容状态
                            Text(aiService.currentResponse)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id("response")
                                .padding(.bottom, 4)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ContentHeightPreferenceKey.self,
                                        value: geo.size.height
                                    )
                                })
                                .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                                    if height > 0 {
                                        responseHeight = height
                                        updateTotalHeight()
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: aiService.currentResponse) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("response", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            // 初始化时就计算一个基础高度
            previousPrompt = prompt
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateInitialHeight()
            }
            
            Task { @MainActor in
                await aiService.streamChat(prompt: prompt)
            }
        }
        .onChange(of: prompt) { oldValue, newValue in
            // 如果问题变化，重置回复高度
            if oldValue != newValue && previousPrompt != newValue {
                previousPrompt = newValue
                responseHeight = 0
                updateInitialHeight()
            }
        }
        .onDisappear {
            aiService.cancelStream()
        }
    }
    
    private func updateTotalHeight() {
        let totalHeight = if aiService.currentResponse.isEmpty {
            contentHeight + 50 // 问题高度 + "正在思考中"文本高度
        } else {
            contentHeight + min(responseHeight, 500) // 问题高度 + 回复高度（限制最大高度）
        }
        
        // 通知父视图更新高度
        onHeightChange?(totalHeight)
    }
    
    private func updateInitialHeight() {
        // 确保初始状态下有一个合理的高度
        responseHeight = 0 // 重置回复高度
        onHeightChange?(contentHeight + 120)
    }
} 