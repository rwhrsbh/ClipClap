// MARK: - Published Properties

/// Clipboard history
@Published private(set) var clipboardHistory: [ClipboardItem] = []

/// Clipboard manager state
@Published private(set) var state: ClipboardManagerState = .initializing

/// Available manager settings
@Published var settings = ClipboardManagerSettings()

/// Auto-launch state
@Published private(set) var isAutoLaunchEnabled: Bool = false

/// Додаємо опубліковану властивість для відстеження стану дозволів
@Published private(set) var isAccessibilityPermissionGranted: Bool = false

// ... existing code ...

/// Перевіряє статус дозволів і оновлює стан
func checkPermissionsStatus() {
    let trusted = AXIsProcessTrusted()
    log("Checking permissions: \(trusted ? "granted" : "not granted")")
    
    // Оновлюємо опубліковану властивість
    isAccessibilityPermissionGranted = trusted
    
    if trusted {
        registerHotKey()
    }
}

/// Запитує дозволи на доступ до функцій доступності
func requestPermissions() {
    log("Requesting permissions for hotkeys")

    // Створюємо запит з явним діалогом
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    
    // Розпочинаємо серію перевірок дозволів з короткими інтервалами
    var checkCount = 0
    let maxChecks = 20 // перевіряти максимум 20 разів
    
    func checkPermissionsAndUpdate() {
        checkCount += 1
        
        let trusted = AXIsProcessTrusted()
        
        // Завжди оновлюємо в головному потоці
        DispatchQueue.main.async {
            // Якщо дозволи надані або досягнуто максимальну кількість перевірок
            if trusted {
                self.log("Permissions granted after check #\(checkCount)!")
                
                // Оновлюємо стан
                self.isAccessibilityPermissionGranted = true
                self.state = .ready
                
                // Реєструємо гарячі клавіші
                self.registerHotKey()
                
                // Показуємо повідомлення
                let successAlert = NSAlert()
                successAlert.messageText = "Permissions granted!"
                successAlert.informativeText = "Cmd+Shift+V hotkeys are now active."
                successAlert.addButton(withTitle: "OK")
                successAlert.runModal()
            }
            else if checkCount < maxChecks {
                // Продовжуємо перевірку через 500 мс
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkPermissionsAndUpdate()
                }
            }
            else {
                self.log("Permissions check timed out after \(checkCount) attempts")
            }
        }
    }
    
    // Розпочинаємо перевірку через 1 секунду після запиту
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        checkPermissionsAndUpdate()
    }
}

// ... existing code ...

/// Обробляє активацію програми
@objc private func applicationDidBecomeActive() {
    // При активації перевіряємо статус дозволів
    checkPermissionsStatus()
}

/// Starts application with current permissions
func startApplicationWithCurrentPermissions() {
    log("Starting the application")
    
    // Check permissions
    let trusted = AXIsProcessTrusted()
    isAccessibilityPermissionGranted = trusted
    
    if trusted {
        log("Accessibility permissions granted")
        state = .ready
        registerHotKey()
    } else {
        log("Accessibility permissions not granted")
        state = .needsPermissions
    }
    
    // Start basic monitoring in any case
    startBasicMonitoring(force: true)
}

/// Налаштовує повідомлення
private func setupNotifications() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(applicationWillTerminate),
        name: NSApplication.willTerminateNotification,
        object: nil
    )
    
    // Додаємо обробку активації додатку
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(applicationDidBecomeActive),
        name: NSApplication.didBecomeActiveNotification,
        object: nil
    )
    
    // Додаємо обробники для зміни фокусу та активності вікна
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidBecomeKey),
        name: NSWindow.didBecomeKeyNotification,
        object: nil
    )
    
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(applicationDidBecomeActive),
        name: NSApplication.didBecomeActiveNotification,
        object: nil
    )
    
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(checkPermissionsAfterDelay),
        name: NSApplication.didUpdateNotification,
        object: nil
    )
}

/// Обробляє активацію вікна
@objc private func windowDidBecomeKey(_ notification: Notification) {
    // Перевіряємо дозволи при активації вікна
    checkPermissionsStatus()
}

/// Перевіряє дозволи з затримкою
@objc private func checkPermissionsAfterDelay() {
    // Перевіряємо дозволи з невеликою затримкою
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.checkPermissionsStatus()
    }
}

init() {
    log("Clipboard manager initialization")
    
    // Ініціалізуємо властивість стану доступів
    isAccessibilityPermissionGranted = AXIsProcessTrusted()
    
    // Check auto-launch status
    checkAutoLaunchStatus()
    
    // If first launch - enable auto-launch by default
    let firstLaunch = !UserDefaults.standard.bool(forKey: "ClipClap_HasLaunched")
    if firstLaunch {
        log("First launch - setting up auto-launch")
        UserDefaults.standard.set(true, forKey: "ClipClap_HasLaunched")
        toggleAutoLaunch(enabled: true)
    }
} 