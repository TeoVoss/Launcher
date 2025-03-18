//
//  LauncherApp.swift
//  Launcher
//
//  Created by 周聪 on 2025/3/13.
//

import SwiftUI
import HotKey
import AppKit

// 单例管理器，保存全局状态
class AppManager {
    static let shared = AppManager()
    
    private var _settingsManager: SettingsManager?
    
    private init() {}
    
    // 线程安全地获取设置管理器
    @MainActor
    func getSettingsManager() -> SettingsManager {
        if _settingsManager == nil {
            _settingsManager = SettingsManager()
        }
        return _settingsManager!
    }
}

@main
struct LauncherApp: App {
    // 使用SwiftUI标准方式声明应用代理
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 应用场景
    var body: some Scene {
        // 设置窗口场景
        Settings {
            NavigationView {
                SettingsViewLoader()
            }
        }
        
        // 添加一个空的窗口组，避免SwiftUI自动创建窗口
        WindowGroup {
            EmptyView().frame(width: 0, height: 0).hidden()
        }
    }
}

// 专门用于加载设置视图的组件
struct SettingsViewLoader: View {
    @State private var settingsManager: SettingsManager?
    
    var body: some View {
        Group {
            if let manager = settingsManager {
                SettingsView(settingsManager: manager)
            } else {
                ProgressView()
                    .onAppear {
                        Task { @MainActor in
                            settingsManager = AppManager.shared.getSettingsManager()
                        }
                    }
            }
        }
    }
}

// 应用代理类
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var window: NSWindow?
    private var hotKey: HotKey?
    private var spotlightView: SpotlightView?
    private var windowDelegate: WindowDelegate?
    private var aiService: AIService?
    
    // 标准的应用启动方法
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 在主线程上异步初始化UI组件
        Task { @MainActor in
            // 获取设置
            let settingsManager = AppManager.shared.getSettingsManager()
            
            // 初始化AI服务
            self.aiService = AIService(settingsManager: settingsManager)
            
            // 设置UI组件
            setupStatusBar()
            setupHotKey()
            setupMainWindow()
            
            // 设置为辅助应用模式
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Launcher")
            
            // 创建菜单
            let menu = NSMenu()
            
            // 添加设置菜单项
            let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)
            
            // 添加分隔线
            menu.addItem(NSMenuItem.separator())
            
            // 添加退出菜单项
            let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.addItem(quitItem)
            
            // 设置菜单和操作
            statusItem?.menu = menu
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }
    
    @objc private func statusItemClicked(sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // 右键点击显示菜单
            statusItem?.button?.performClick(nil)
        } else {
            // 左键点击显示窗口
            toggleWindow()
        }
    }
    
    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    private func setupMainWindow() {
        // 确保AIService已初始化
        guard let aiService = self.aiService else { return }
        
        // 创建窗口
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 44),
            styleMask: [.borderless, .fullSizeContentView, .titled, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // 配置窗口属性
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("LauncherWindow")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.hasShadow = true
        window.animationBehavior = .utilityWindow
        
        // 隐藏标题栏按钮
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        
        // 设置内容视图
        let spotlightView = SpotlightView(aiService: aiService)
        self.spotlightView = spotlightView
        window.contentView = NSHostingView(
            rootView: spotlightView
                .environment(\.colorScheme, .dark)
        )
        
        // 设置圆角
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 8
            contentView.layer?.masksToBounds = true
        }
        
        // 设置窗口代理
        let delegate = WindowDelegate(onWindowResignKey: { [weak self] in
            self?.hideWindow()
        })
        self.windowDelegate = delegate
        window.delegate = delegate
        
        self.window = window
    }
    
    private func hideWindow() {
        guard let window = self.window, let spotlightView = self.spotlightView else { return }
        
        // 重置搜索状态
        spotlightView.resetSearch()
        
        // 重置窗口大小并隐藏
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setContentSize(NSSize(width: 680, height: 44))
        } completionHandler: {
            self.window?.orderOut(nil)
        }
    }
    
    private func setupHotKey() {
        // 设置 Command + control + 1 快捷键
        hotKey = HotKey(key: .one, modifiers: [.command, .control])
        
        hotKey?.keyDownHandler = { [weak self] in
            self?.toggleWindow()
        }
    }
    
    @objc private func toggleWindow() {
        guard let window = self.window else { return }
        
        if window.isVisible {
            hideWindow()
        } else {
            // 计算窗口位置（屏幕中央偏上）
            if let screen = NSScreen.main {
                let screenFrame = screen.frame
                let windowFrame = window.frame
                let x = (screenFrame.width - windowFrame.width) / 2
                let y = screenFrame.height * 0.6
                
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            // 显示窗口并设置焦点
            window.setContentSize(NSSize(width: 680, height: 44))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            // 设置焦点到搜索框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.spotlightView?.requestFocus()
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

// 窗口代理类
class WindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowResignKey: () -> Void
    
    init(onWindowResignKey: @escaping () -> Void) {
        self.onWindowResignKey = onWindowResignKey
        super.init()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        onWindowResignKey()
    }
}
