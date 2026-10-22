import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 纯菜单栏模式：隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // SwiftUI 窗口创建是异步的，在应用激活后捕获更可靠
        if mainWindow == nil {
            mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) ?? NSApp.windows.first
            mainWindow?.isReleasedWhenClosed = false
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleWindow()
        return true
    }
    
    // MARK: - Status Item
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem?.button else { return }
        
        // 菜单栏使用原生精致的 SF Symbol（日历签到打勾），自适应浅色/暗色模式，避免彩色位图被压缩成实心黑方块
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let img = NSImage(systemSymbolName: "calendar.badge.checkmark", accessibilityDescription: "AutoCheckin")?.withSymbolConfiguration(config) {
            img.isTemplate = true
            button.image = img
        } else {
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "AutoCheckin")
        }
        
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // 右键：显示快捷菜单（现代写法：临时赋值 menu 属性）
            let menu = NSMenu()
            let openItem = NSMenuItem(title: "打开 AutoCheckin", action: #selector(showWindow), keyEquivalent: "")
            openItem.target = self
            // 退出的 terminate: 实现在 NSApplication 上；
            // 显式指给 NSApp，避免 nil target 在无 key window 的菜单栏场景下校验失败被置灰
            let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quitItem.target = NSApp
            menu.addItem(openItem)
            menu.addItem(.separator())
            menu.addItem(quitItem)
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil   // 点击后清空，保留左键自定义逻辑
        } else {
            // 左键：切换窗口显示/隐藏
            toggleWindow()
        }
    }
    
    @objc private func showWindow() {
        let target = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) ?? NSApp.windows.first
        target?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func toggleWindow() {
        let target = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) ?? NSApp.windows.first
        guard let window = target else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        if window.isVisible && NSApp.isActive {
            // 窗口可见且应用在前台 → 隐藏
            window.orderOut(nil)
            NSApp.hide(nil)
        } else {
            // 否则 → 唤出
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct AutoCheckinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let manager: CheckinManager
    
    init() {
        let m = CheckinManager()
        self.manager = m
        // 启动时自动扫描本地账号
        m.scanAll()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .frame(minWidth: 740, idealWidth: 820, minHeight: 520, idealHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
