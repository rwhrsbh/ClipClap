import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var clipboardManager: ClipboardManager!
    var window: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize clipboard manager
        clipboardManager = ClipboardManager()
        
        // Remove icon from Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Ініціалізуємо вікно, але не показуємо його автоматично
        // Воно буде показано в методі setupMainWindow, лише якщо showStartupScreen=true
        clipboardManager.setupMainWindow()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Code for application termination
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If there's no window or it's not visible, show the main window
        if !flag {
            clipboardManager.showMainWindow()
        }
        return true
    }
} 