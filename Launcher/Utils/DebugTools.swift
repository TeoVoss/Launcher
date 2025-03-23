import SwiftUI

/// 视图调试工具集合
enum DebugTools {
    /// 调试边框颜色
    enum BorderColor {
        case red    // 用于搜索栏
        case green  // 用于结果列表
        case blue   // 用于内容区域
        case purple // 用于AI响应
        case orange // 用于文件搜索
        case yellow // 用于其他组件
        
        var color: Color {
            switch self {
            case .red: return .red
            case .green: return .green
            case .blue: return .blue
            case .purple: return .purple
            case .orange: return .orange
            case .yellow: return .yellow
            }
        }
    }
    
    /// 是否启用调试模式 - 全局UI调试开关
    static var debugModeEnabled: Bool = false
    
    /// 是否启用调试边框
    static var debugBordersEnabled: Bool = false
    
    /// 是否启用调试信息面板
    static var debugInfoEnabled: Bool = false
    
    /// 是否启用尺寸报告（控制台输出）
    static var sizeReportingEnabled: Bool = false
    
    /// 一键开启或关闭所有调试功能
    static func setDebugMode(enabled: Bool) {
        debugModeEnabled = enabled
        debugBordersEnabled = enabled
        debugInfoEnabled = enabled
        sizeReportingEnabled = enabled
    }
}

/// 调试边框修饰符
struct DebugBorderModifier: ViewModifier {
    let color: DebugTools.BorderColor
    let width: CGFloat
    let enabled: Bool
    
    /// 初始化边框修饰符
    /// - Parameters:
    ///   - color: 边框颜色
    ///   - width: 边框宽度
    ///   - enabled: 是否启用（默认跟随全局设置）
    init(color: DebugTools.BorderColor, width: CGFloat = 1.0, enabled: Bool? = nil) {
        self.color = color
        self.width = width
        self.enabled = enabled ?? (DebugTools.debugModeEnabled && DebugTools.debugBordersEnabled)
    }
    
    func body(content: Content) -> some View {
        if enabled {
            content
                .overlay(
                    Rectangle()
                        .stroke(color.color, lineWidth: width)
                )
                .overlay(
                    Text(String(describing: color))
                        .font(.system(size: 8))  // 缩小字体
                        .foregroundColor(color.color)
                        .padding(1)  // 减少内边距
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(2)
                        .padding(1),  // 减少外边距
                    alignment: .topLeading
                )
        } else {
            content
        }
    }
}

/// 调试面板修饰符
struct DebugInfoModifier: ViewModifier {
    let info: String
    let enabled: Bool
    
    init(info: String, enabled: Bool? = nil) {
        self.info = info
        self.enabled = enabled ?? (DebugTools.debugModeEnabled && DebugTools.debugInfoEnabled)
    }
    
    func body(content: Content) -> some View {
        if enabled {
            content
                .overlay(
                    VStack(alignment: .leading, spacing: 1) {  // 减少行间距
                        Spacer()
                        Text("调试信息")
                            .font(.system(size: 8, weight: .bold))  // 缩小字体
                            .padding(.bottom, 1)  // 减少底部间距
                        Text(info)
                            .font(.system(size: 8))  // 缩小字体
                    }
                    .frame(maxWidth: 100, alignment: .leading)  // 限制最大宽度
                    .padding(4)  // 减少内边距
                    .background(Color.black.opacity(0.6))  // 降低不透明度
                    .foregroundColor(.white)
                    .cornerRadius(4)  // 缩小圆角
                    .padding(4),  // 减少外边距
                    alignment: .bottomLeading  // 改为左下角显示
                )
        } else {
            content
        }
    }
}

/// 视图尺寸检查修饰符
struct SizeReporterModifier: ViewModifier {
    let name: String
    let onSizeChange: (CGSize) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: SizePreferenceKey.self, value: geo.size)
                        .onPreferenceChange(SizePreferenceKey.self) { size in
                            if DebugTools.debugModeEnabled && DebugTools.sizeReportingEnabled {
                                print("【尺寸报告】\(name): 宽度=\(size.width), 高度=\(size.height)")
                            }
                            onSizeChange(size)
                        }
                }
            )
    }
}

/// 尺寸首选项键
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// 为View添加调试边框的扩展
extension View {
    /// 添加调试边框
    func debugBorder(_ color: DebugTools.BorderColor, width: CGFloat = 1.0, enabled: Bool? = nil) -> some View {
        modifier(DebugBorderModifier(color: color, width: width, enabled: enabled))
    }
    
    /// 添加调试信息面板
    func debugInfo(_ info: String, enabled: Bool? = nil) -> some View {
        modifier(DebugInfoModifier(info: info, enabled: enabled))
    }
    
    /// 报告视图尺寸
    func reportSize(name: String, onChange: @escaping (CGSize) -> Void = { _ in }) -> some View {
        modifier(SizeReporterModifier(name: name, onSizeChange: onChange))
    }
} 