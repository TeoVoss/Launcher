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
                ScrollView {
                    Text(aiService.currentResponse.isEmpty ? "正在思考中..." : aiService.currentResponse)
                        .font(.system(size: 14))
                        .foregroundColor(aiService.currentResponse.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.2), value: aiService.currentResponse)
                        .onChange(of: aiService.currentResponse) { _, newValue in
                            print("[AIResponseView] 响应内容更新，长度：\(newValue.count)")
                        }
                }
                
                // 加载动画始终显示在底部
                if aiService.isStreaming {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(height: 16)
                        Spacer()
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