import Foundation

struct AISettings: Codable {
    var endpoint: String
    var apiKey: String
    var model: String
    
    static var defaultSettings: AISettings {
        return AISettings(
            endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            apiKey: "",
            model: "qwen-max-latest"
        )
    }
}

@MainActor
class SettingsManager: ObservableObject {
    @Published var aiSettings: AISettings
    private let aiSettingsKey = "aiSettings"
    
    init() {
        if let data = UserDefaults.standard.data(forKey: aiSettingsKey),
           let settings = try? JSONDecoder().decode(AISettings.self, from: data) {
            self.aiSettings = settings
        } else {
            self.aiSettings = AISettings.defaultSettings
        }
    }
    
    func saveSettings() {
        if let data = try? JSONEncoder().encode(aiSettings) {
            UserDefaults.standard.set(data, forKey: aiSettingsKey)
        }
    }
    
    // 验证设置是否可用
    func validateSettings(endpoint: String, apiKey: String, model: String) async -> (Bool, String) {
        guard let url = URL(string: endpoint) else {
            return (false, "无效的URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "测试连接"]
            ],
            "stream": true,
            "max_tokens": 10
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return (false, "请求体序列化失败: \(error.localizedDescription)")
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    return (true, "验证成功")
                } else {
                    return (false, "HTTP错误: \(httpResponse.statusCode)")
                }
            } else {
                return (false, "无效的响应")
            }
        } catch {
            return (false, "请求失败: \(error.localizedDescription)")
        }
    }
} 