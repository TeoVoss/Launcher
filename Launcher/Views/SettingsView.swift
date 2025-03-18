import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    
    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var isValidating = false
    @State private var validationMessage = ""
    @State private var isValidationSuccess = false
    @State private var selectedTab = 0
    
    // 常用模型列表
    private let commonModels = [
        "qwen-max-latest",
        "qwen-max",
        "qwen-plus",
        "qwen-turbo"
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航栏
            VStack(spacing: 25) {
                TabItem(title: "API设置", icon: "key.fill", isSelected: selectedTab == 0)
                    .onTapGesture { selectedTab = 0 }
                
                TabItem(title: "高级", icon: "gearshape", isSelected: selectedTab == 1)
                    .onTapGesture { selectedTab = 1 }
                
                TabItem(title: "关于", icon: "info.circle", isSelected: selectedTab == 2)
                    .onTapGesture { selectedTab = 2 }
                
                Spacer()
            }
            .frame(width: 120)
            .padding(.top, 20)
            .background(Color(NSColor.controlBackgroundColor))
            
            // 右侧内容区
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 标题
                    Text(tabTitle)
                        .font(.title2)
                        .bold()
                        .padding(.top, 10)
                        .padding(.bottom, 5)
                    
                    if selectedTab == 0 {
                        apiSettingsView
                    } else if selectedTab == 1 {
                        advancedSettingsView
                    } else {
                        aboutView
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            // 加载当前设置
            endpoint = settingsManager.aiSettings.endpoint
            apiKey = settingsManager.aiSettings.apiKey
            model = settingsManager.aiSettings.model
        }
    }
    
    private var tabTitle: String {
        switch selectedTab {
        case 0:
            return "API设置"
        case 1:
            return "高级设置"
        case 2:
            return "关于"
        default:
            return ""
        }
    }
    
    private var apiSettingsView: some View {
        VStack(spacing: 20) {
            // API设置卡片
            VStack(spacing: 0) {
                SettingField(icon: "link", title: "API端点") {
                    TextField("https://dashscope.aliyuncs.com/...", text: $endpoint)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .autocorrectionDisabled()
                }
                
                Divider().padding(.leading, 50)
                
                SettingField(icon: "key", title: "API密钥") {
                    SecureField("输入您的API密钥", text: $apiKey)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .autocorrectionDisabled()
                }
                
                Divider().padding(.leading, 50)
                
                SettingField(icon: "cpu", title: "选择模型") {
                    Picker("", selection: $model) {
                        ForEach(commonModels, id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                        Text("自定义").tag("custom")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                }
                
                if model == "custom" {
                    Divider().padding(.leading, 50)
                    
                    SettingField(icon: "pencil", title: "自定义模型") {
                        TextField("输入自定义模型名称", text: $model)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .autocorrectionDisabled()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // 验证与保存按钮卡片
            VStack {
                Button(action: validateAndSave) {
                    HStack {
                        Image(systemName: "checkmark.shield")
                        if isValidating {
                            Text("验证中...")
                        } else {
                            Text("验证并保存")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(BorderedButtonStyle(tint: .pink))
                .controlSize(.large)
                .disabled(isValidating || endpoint.isEmpty || apiKey.isEmpty || model.isEmpty)
                
                if !validationMessage.isEmpty {
                    HStack {
                        Image(systemName: isValidationSuccess ? "checkmark.circle" : "xmark.circle")
                        Text(validationMessage)
                    }
                    .foregroundColor(isValidationSuccess ? .green : .red)
                    .padding(.top, 8)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var advancedSettingsView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 0) {
                ToggleSetting(icon: "magnifyingglass", title: "默认启用联网搜索", isOn: Binding(get: { true }, set: { _ in }))
                
                Divider().padding(.leading, 50)
                
                ToggleSetting(icon: "brain", title: "使用高级思考能力", isOn: Binding(get: { false }, set: { _ in }))
                
                Divider().padding(.leading, 50)
                
                ToggleSetting(icon: "clock", title: "保存对话历史", isOn: Binding(get: { true }, set: { _ in }))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var aboutView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.pink)
                
                Text("Launcher")
                    .font(.title)
                    .bold()
                
                Text("版本 1.0.0")
                    .foregroundColor(.secondary)
                
                Text("这是一个高效的搜索和AI助手应用，可以帮助您快速访问信息和获得智能回答。")
                    .multilineTextAlignment(.center)
                    .padding()
                
                Button("查看源代码") {
                    // 打开GitHub链接
                    NSWorkspace.shared.open(URL(string: "https://github.com/yourusername/launcher")!)
                }
                .buttonStyle(.plain)
                .foregroundColor(.pink)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func validateAndSave() {
        isValidating = true
        validationMessage = "正在验证..."
        
        Task {
            let (success, message) = await settingsManager.validateSettings(
                endpoint: endpoint,
                apiKey: apiKey,
                model: model
            )
            
            await MainActor.run {
                isValidationSuccess = success
                validationMessage = message
                isValidating = false
                
                if success {
                    // 保存设置
                    settingsManager.aiSettings.endpoint = endpoint
                    settingsManager.aiSettings.apiKey = apiKey
                    settingsManager.aiSettings.model = model
                    settingsManager.saveSettings()
                }
            }
        }
    }
}

// 按钮样式
struct BorderedButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(configuration.isPressed ? 0.7 : 1.0))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

// 左侧导航选项项
struct TabItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isSelected ? .pink : .gray)
            
            Text(title)
                .font(.caption)
                .foregroundColor(isSelected ? .pink : .gray)
        }
        .frame(width: 100, height: 60)
    }
}

// 设置字段组件
struct SettingField<Content: View>: View {
    let icon: String
    let title: String
    let content: Content
    
    init(icon: String, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.pink)
                .frame(width: 30)
            
            Text(title)
                .frame(width: 80, alignment: .leading)
            
            content
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
    }
}

// 开关设置组件
struct ToggleSetting: View {
    let icon: String
    let title: String
    let isOn: Binding<Bool>
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.pink)
                .frame(width: 30)
            
            Text(title)
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.vertical, 12)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settingsManager: SettingsManager())
            .frame(width: 600, height: 400)
    }
} 