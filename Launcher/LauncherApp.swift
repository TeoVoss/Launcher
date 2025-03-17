//
//  LauncherApp.swift
//  Launcher
//
//  Created by 周聪 on 2025/3/13.
//

import SwiftUI
import HotKey
import AppKit

@main
struct LauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var window: NSWindow?
    private var hotKey: HotKey?
    private var spotlightView: SpotlightView?
    private var windowDelegate: WindowDelegate?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Launcher")
        }
        
        // 创建主窗口
        setupMainWindow()
        
        // 设置全局快捷键
        setupHotKey()
        
        // 注册点击事件
        statusItem?.button?.action = #selector(toggleWindow)
        
        // 确保应用在后台运行，但不显示在Dock
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMainWindow() {
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
        
        // 允许窗口调整大小但隐藏标题栏按钮
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        
        // 设置内容视图
        let spotlightView = SpotlightView()
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
        
        // 设置窗口代理（使用强引用）
        let delegate = WindowDelegate(onWindowResignKey: { [weak self] in
            self?.hideWindow()
        })
        self.windowDelegate = delegate
        window.delegate = delegate
        
        self.window = window
    }
    
    private func hideWindow() {
        guard let window = self.window else { return }
        
        // 先重置搜索状态
        spotlightView?.resetSearch()
        
        // 隐藏窗口时重置大小
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
            
            // 先设置初始大小，避免从上次的大小开始动画
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
