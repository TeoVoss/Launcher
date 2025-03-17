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
    // 添加引用回调，用于外部获取视图实例
    var onViewCreated: ((AIResponseView) -> Void)? = nil
    @State private var scrollViewHeight: CGFloat = 0
    @State private var currentPrompt: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 单一消息流视图
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 显示所有对话（包括正在进行的对话）
                        ForEach(aiService.conversationHistory) { message in
                            // 根据消息类型设置不同的样式
                            if message.role == "user" {
                                // 用户消息
                                Text(message.content)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .padding(.bottom, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, aiService.conversationHistory.firstIndex(of: message)! > 0 && 
                                             aiService.conversationHistory[aiService.conversationHistory.firstIndex(of: message)! - 1].role == "assistant" ? 20 : 4) // 增加问题之间的间距
                                    .id(message.id)
                            } else {
                                // AI回复
                                let index = aiService.conversationHistory.firstIndex(of: message)!
                                if message.content.isEmpty && index == aiService.activeResponseIndex {
                                    // 显示"正在思考中"状态
                                    HStack(spacing: 4) {
                                        Text("正在思考中...")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                        
                                        ProgressView()
                                            .scaleEffect(0.5)
                                            .frame(height: 16)
                                    }
                                    .id("thinking_\(index)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                } else {
                                    // 显示AI回复内容
                                    Text(message.content)
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .id(message.id)
                                        .padding(.bottom, 4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: ContentHeightPreferenceKey.self,
                            value: geo.size.height
                        )
                    })
                    .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                        scrollViewHeight = height
                        updateTotalHeight()
                    }
                }
                .onChange(of: aiService.conversationHistory) { _, newValue in
                    // 当对话历史更新时（添加新消息或现有消息更新内容），滚动到最新消息
                    if !newValue.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(newValue.last!.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            // 第一次显示视图时，记录当前提示并发送请求
            currentPrompt = prompt
            
            // 调用回调，使外部能引用此视图
            onViewCreated?(self)
            
            Task { @MainActor in
                await aiService.streamChat(prompt: prompt)
            }
        }
        .onChange(of: prompt) { oldValue, newValue in
            // 更新当前记录的提示，但不触发请求
            // 请求将由SpotlightView的handleSubmit方法在用户按下Enter时触发
            currentPrompt = newValue
        }
        .onDisappear {
            aiService.cancelStream()
        }
    }
    
    // 添加一个方法来手动发送请求
    func sendRequest() async {
        if !aiService.isStreaming {
            await aiService.streamChat(prompt: currentPrompt)
        }
    }
    
    private func updateTotalHeight() {
        let totalHeight = min(scrollViewHeight + 20, 500) // 滚动视图高度 + 上下内边距，最大高度限制
        
        // 通知父视图更新高度
        onHeightChange?(totalHeight)
    }
} 