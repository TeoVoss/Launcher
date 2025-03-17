import Foundation

@MainActor
class AIService: ObservableObject {
    @Published var isStreaming = false
    @Published var currentResponse = ""
    
    private let endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    private let apiKey = "sk-d2cfb2a428af4e36a1ae89dda611d74b"
    private let model = "qwen-max-latest"
    private var buffer = ""
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    
    func cancelStream() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
        isStreaming = false
        buffer = ""
    }
    
    func streamChat(prompt: String) async {
        isStreaming = true
        currentResponse = ""
        buffer = ""
        
        guard let url = URL(string: endpoint) else {
            currentResponse = "错误：无效的 URL"
            isStreaming = false
            return
        }
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "请用这样的风格回答他：简洁、生动。请基于事实回答，不要捏造"
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "stream": true
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            currentResponse = "错误：请求体序列化失败"
            isStreaming = false
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
                    self.currentResponse = self.buffer
                }
            },
            completion: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isStreaming = false
                }
            },
            error: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if (error as NSError).code != NSURLErrorCancelled {
                        self.currentResponse = "错误：\(error.localizedDescription)"
                    }
                    self.isStreaming = false
                }
            }
        )
        
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
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
        
        // 尝试按行分割并处理数据
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
            // 处理缓冲区中剩余的数据
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