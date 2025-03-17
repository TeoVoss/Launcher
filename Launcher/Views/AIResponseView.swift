import SwiftUI

struct AIResponseView: View {
    @ObservedObject var aiService: AIService
    let prompt: String
    let onEscape: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 用户问题
            Text(prompt)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // AI 回复区域
            VStack(alignment: .leading, spacing: 8) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if aiService.currentResponse.isEmpty {
                                HStack(spacing: 4) {
                                    Text("正在思考中...")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                    
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(height: 16)
                                }
                                .id("loading")
                            }
                            
                            if !aiService.currentResponse.isEmpty {
                                Text(aiService.currentResponse)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .animation(.easeInOut(duration: 0.2), value: aiService.currentResponse)
                                    .id("response")
                            }
                        }
                        .onChange(of: aiService.currentResponse) { _, _ in
                            withAnimation {
                                proxy.scrollTo("response", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("[AIResponseView] 视图出现")
            Task { @MainActor in
                print("[AIResponseView] 开始请求 AI 服务")
                await aiService.streamChat(prompt: prompt)
            }
        }
        .onDisappear {
            print("[AIResponseView] 视图消失")
            aiService.cancelStream()
        }
    }
} 