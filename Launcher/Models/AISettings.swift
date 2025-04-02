import Foundation
import SwiftUI

// 定义主题模式枚举
enum ThemeMode: String, Codable {
    case dark = "dark"         // 深色模式
    case light = "light"       // 浅色模式
    case system = "system"     // 跟随系统
}

struct AISettings: Codable {
    var endpoint: String
    var apiKey: String
    var model: String
    var themeMode: ThemeMode   // 添加主题模式设置
    
    static var defaultSettings: AISettings {
        return AISettings(
            endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            apiKey: "",
            model: "qwen-max-latest",
            themeMode: .dark    // 默认深色模式
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
            print(self.aiSettings)
        }
    }
    
    // 获取当前应该使用的颜色模式
    func getCurrentColorScheme() -> ColorScheme? {
        switch aiSettings.themeMode {
        case .dark:
            return .dark
        case .light:
            return .light
        case .system:
            return nil // 返回nil表示跟随系统
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
