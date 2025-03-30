import SwiftUI
import AppKit

// DraggableView 用于实现窗口拖动
struct DraggableView: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        let view = DraggableNSView()
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

// 自定义 NSView 子类来处理拖动
class DraggableNSView: NSView {
    private var isDragging = false
    private var initialMouseLocation: NSPoint?
    private var initialWindowLocation: NSPoint?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // 确保视图已添加到窗口后再设置
        if self.window != nil {
            // 视图已添加到窗口，可以安全初始化手势
            self.window?.makeFirstResponder(nil)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowLocation = window.frame.origin
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = window,
              let initialMouseLocation = initialMouseLocation,
              let initialWindowLocation = initialWindowLocation else { return }
        
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y
        
        let newOrigin = NSPoint(
            x: initialWindowLocation.x + deltaX,
            y: initialWindowLocation.y + deltaY
        )
        
        window.setFrameOrigin(newOrigin)
    }
    
    override func mouseUp(with event: NSEvent) {
        initialMouseLocation = nil
        initialWindowLocation = nil
        
        if let window = window {
            let frame = window.frame
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: "SpotlightWindowFrame")
            UserDefaults.standard.synchronize()
        }
    }
}

struct SearchBarView: View {
    // 使用静态ID确保视图标识一致
    private static let viewIdentifier = "SearchBarView"
    
    @Binding var searchText: String
    @FocusState private var isFocused: Bool
    
    // 固定搜索框高度
    private let searchBarHeight: CGFloat = 44
    
    // 状态跟踪 - 使用更精确的状态管理
    @State private var isTextEmpty: Bool = true
    @State private var isClearing: Bool = false
    @State private var lastProcessedText: String = ""
    
    // 批处理状态变更，防止重复渲染
    @State private var pendingStateUpdate: DispatchWorkItem? = nil
    
    var body: some View {
        // 锁定外层容器结构，防止重建
        VStack(spacing: 0) {
            // 搜索框容器 - 固定高度和结构
            ZStack {
                // 拖动层 - 永远存在
                DraggableView()
                    .allowsHitTesting(true) 
                    // 使用调试工具控制边框显示
                    .debugBorder(.yellow, width: 0.5)
                
                // 输入区域 - 固定结构
                HStack(spacing: 8) {
                    // 搜索图标
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    // 输入区域 - 使用稳定的ZStack结构
                    ZStack(alignment: .leading) {
                        // 占位符文本 - 通过opacity控制显示，而不是条件渲染
                        Text("搜索")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.7))
                            .opacity(isTextEmpty ? 1 : 0)
                            .allowsHitTesting(false)
                        
                        // 输入框 - 永远显示
                        TextField("", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 24))
                            .focused($isFocused)
                            .onSubmit {
                                // 确保保持焦点
                                isFocused = true
                            }
                            // 使用调试工具控制边框显示
                            .debugBorder(.blue, width: 0.5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: searchBarHeight, alignment: .leading)
                    // 使用调试工具控制边框显示
                    .debugBorder(.green, width: 0.5)
                }
                .padding(.horizontal, 16)
                .frame(height: searchBarHeight)
                // 使用调试工具控制边框显示
                .debugBorder(.red, width: 0.5)
            }
            .frame(height: searchBarHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .opacity(0.8)
            )
        }
        // 固定ID确保视图不重建
        .id(Self.viewIdentifier)
        .reportSize(name: "SearchBarView-Outer") // 报告尺寸以便调试
        .onAppear {
            // 初始化视图状态
            isTextEmpty = searchText.isEmpty
            lastProcessedText = searchText
            
            // 确保获得焦点
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.1))
                if Task.isCancelled { return }
                isFocused = true
            }
        }
        .onChange(of: searchText) { newValue in
            // 清除中或内容相同则跳过处理
            if isClearing || newValue == lastProcessedText { return }
            
            // 取消之前的待处理更新
            pendingStateUpdate?.cancel()
            
            // 创建新的批处理任务
            let updateTask = DispatchWorkItem {
                // 使用动画更新空状态
                withAnimation(.easeInOut(duration: 0.1)) {
                    self.isTextEmpty = newValue.isEmpty
                }
                
                // 记录已处理的文本
                self.lastProcessedText = newValue
            }
            
            // 保存此次更新任务
            pendingStateUpdate = updateTask
            
            // 延迟执行，允许多个快速输入合并
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.03))
                if Task.isCancelled {
                    updateTask.cancel()
                    return
                }
                updateTask.perform()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RequestSearchFocus"))) { _ in
            isFocused = true
        }
    }
} 
