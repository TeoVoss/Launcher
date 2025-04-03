import Foundation
import Combine

// String扩展
extension String {
    func trim() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// 创建消息结构体，符合Equatable协议
struct ChatMessage: Equatable, Identifiable {
    let id = UUID()
    let role: String
    var content: String
}

@MainActor
class AIService: ObservableObject {
    @Published var isStreaming = false
    @Published var currentResponse = ""
    @Published var responseContent = ""
    // 使用结构体数组替代元组数组
    @Published var conversationHistory: [ChatMessage] = []
    @Published var activeResponseIndex: Int? = nil
    
    // 添加新属性以支持新视图
    @Published var isGenerating: Bool = false
    @Published var response: String = ""
    @Published var isLoading: Bool = false
    
    private var buffer = ""
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var cancellables = Set<AnyCancellable>()
    
    // 将settingsManager作为依赖注入
    private var settingsManager: SettingsManager?
    private var endpoint: String = ""
    private var apiKey: String = ""
    private var model: String = ""
    
    init() {
        // 延迟初始化settingsManager
        Task { @MainActor in
            self.settingsManager = SettingsManager()
            self.updateSettings()
        }
    }
    
    @MainActor
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        self.updateSettings()
        setupSubscriptions()
    }
    
    @MainActor
    private func setupSubscriptions() {
        // 订阅整个aiSettings对象的变化
        self.settingsManager?.$aiSettings
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateSettings()
            }
            .store(in: &cancellables)
    }
    
    private func updateSettings() {
        if let manager = settingsManager {
            self.endpoint = manager.aiSettings.endpoint
            self.apiKey = manager.aiSettings.apiKey
            self.model = manager.aiSettings.model
            
            print("model changed: \(self.model)")
        }
    }
    
    // 添加简化的生成响应方法
    func generateResponse(prompt: String) {
        isGenerating = true
        response = ""
        
        // 启动异步任务
        Task {
            await streamChat(prompt: prompt)
        }
    }
    
    func cancelStream() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
        
        // 修复警告：使用Task避免在视图更新周期内直接修改@Published属性
        Task { @MainActor in
            self.isStreaming = false
            self.isGenerating = false
            self.buffer = ""
            self.activeResponseIndex = nil
        }
    }
    
    func streamChat(prompt: String) async {
        isStreaming = true
        isGenerating = true
        isLoading = true
        buffer = ""
        responseContent = ""
        response = ""
        
        // 直接添加消息，而不是在异步队列中添加
        conversationHistory.append(ChatMessage(role: "user", content: prompt))
        conversationHistory.append(ChatMessage(role: "assistant", content: ""))
        activeResponseIndex = conversationHistory.count - 1
        
        // 使用本地缓存的设置值
        let currentEndpoint = self.endpoint
        let currentApiKey = self.apiKey
        let currentModel = self.model
        
        guard let url = URL(string: currentEndpoint) else {
            let errorMessage = "错误：无效的 URL"
            if let index = activeResponseIndex {
                conversationHistory[index].content = errorMessage
                responseContent = errorMessage
                response = errorMessage
            }
            isStreaming = false
            isGenerating = false
            isLoading = false
            activeResponseIndex = nil
            return
        }
        print(currentModel)
        
        var messages: [[String: Any]] = [
            [
                "role": "system",
                "content": "请用这样的风格回答他：简洁、生动。请基于事实回答，不要捏造"
            ]
        ]
        
        // 因为我们已经直接添加了消息，所以这里可以安全地遍历conversationHistory
        if conversationHistory.count > 0 {
            for i in 0..<conversationHistory.count {
                if i == conversationHistory.count - 1 && conversationHistory[i].role == "assistant" {
                    continue
                }
                let message = conversationHistory[i]
                messages.append([
                    "role": message.role,
                    "content": message.content
                ])
            }
        }
        
        let requestBody: [String: Any] = [
            "model": currentModel,
            "messages": messages,
            "stream": true,
            "enable_search": true
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(currentApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            if let index = activeResponseIndex {
                conversationHistory[index].content = "错误：请求体序列化失败"
                responseContent = "错误：请求体序列化失败"
                response = "错误：请求体序列化失败"
            }
            isStreaming = false
            isGenerating = false
            isLoading = false
            activeResponseIndex = nil
            return
        }
        
        let delegate = StreamDelegate(
            onReceive: { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    let text = String(data: data, encoding: .utf8) ?? ""
                    if text.trimmingCharacters(in: .whitespaces) == "data: [DONE]" {
                        return
                    }
                    
                    let jsonText = text.hasPrefix("data: ") ? String(text.dropFirst(6)) : text
                    
                    guard let jsonData = jsonText.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String else {
                        return
                    }
                    
                    self.buffer += content
                    
                    if let index = self.activeResponseIndex {
                        self.conversationHistory[index].content = self.buffer
                    }
                    
                    self.currentResponse = self.buffer
                    self.responseContent = self.buffer
                    self.response = self.buffer
                }
            },
            completion: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isStreaming = false
                    self.isGenerating = false
                    self.isLoading = false
                    self.activeResponseIndex = nil
                    self.buffer = ""
                }
            },
            error: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    if (error as NSError).code != NSURLErrorCancelled {
                        if let index = self.activeResponseIndex {
                            let errorMessage = "错误：\(error.localizedDescription)"
                            self.conversationHistory[index].content = errorMessage
                            self.responseContent = errorMessage
                            self.response = errorMessage
                        }
                    }
                    
                    self.isStreaming = false
                    self.isGenerating = false
                    self.isLoading = false
                    self.activeResponseIndex = nil
                }
            }
        )
        
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }
    
    func clearConversation() {
        conversationHistory = []
        currentResponse = ""
        responseContent = ""
        response = ""
        activeResponseIndex = nil
        isGenerating = false
    }
    
    // 添加发送查询的方法
    func sendQuery(_ prompt: String) async throws {
        // 如果是空查询，则直接返回
        if prompt.trim().isEmpty {
            isGenerating = false
            isStreaming = false
            return
        }
        
        // 设置状态
        isGenerating = true
        isStreaming = true
        response = ""
        currentResponse = ""
        responseContent = ""
        buffer = ""
        
        // 添加用户消息到历史记录
        let userMessage = ChatMessage(role: "user", content: prompt)
        conversationHistory.append(userMessage)
        
        // 添加临时的助手响应占位符
        let assistantMessage = ChatMessage(role: "assistant", content: "")
        conversationHistory.append(assistantMessage)
        activeResponseIndex = conversationHistory.count - 1
        
        // 执行流式响应
        await streamChat(prompt: prompt)
    }
    
    // 取消所有请求
    func cancelRequests() {
        cancelStream()
        isLoading = false
        isGenerating = false
    }
    
    // 新的发送请求方法，支持SpotlightView
    func sendRequest(prompt: String) async {
        guard !prompt.isEmpty else { return }
        
        isLoading = true
        isGenerating = true
        response = ""
        
        await streamChat(prompt: prompt)
    }
}

class StreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    private let onReceive: (Data) -> Void
    private let onComplete: () -> Void
    private let onError: (Error) -> Void
    
    init(onReceive: @escaping (Data) -> Void,
         completion: @escaping () -> Void,
         error: @escaping (Error) -> Void) {
        self.onReceive = onReceive
        self.onComplete = completion
        self.onError = error
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[..<newlineIndex]
            if !lineData.isEmpty {
                onReceive(lineData)
            }
            buffer.removeSubrange(...newlineIndex)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onError(error)
        } else {
            if !buffer.isEmpty {
                onReceive(buffer)
            }
            onComplete()
        }
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, 
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
    }
}
