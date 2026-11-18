import AppKit

/// macOS 原生应用生命周期代理
/// 负责关闭单机游戏不必要的多标签页合并，并确保点击窗口左上角红叉关闭主窗口时干净退出进程。
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
