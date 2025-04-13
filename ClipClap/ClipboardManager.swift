import Cocoa
import Carbon
import Combine
import SwiftUI
import ServiceManagement

/// Class for managing clipboard and its history
final class ClipboardManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Clipboard history
    @Published private(set) var clipboardHistory: [ClipboardItem] = []
    
    /// Clipboard manager state
    @Published private(set) var state: ClipboardManagerState = .initializing
    
    /// Available manager settings
    @Published var settings = ClipboardManagerSettings()
    
    /// Auto-launch state
    @Published private(set) var isAutoLaunchEnabled: Bool = false
    
    // MARK: - Private Properties
    
    /// Menu bar item
    private var statusItem: NSStatusItem?
    
    /// Popover to display history
    private var popover: NSPopover?
    
    /// Timer for clipboard monitoring
    private var monitorTimer: Timer?
    
    /// Timer for settings auto-save
    private var settingsSaveTimer: Timer?
    
    /// Last clipboard change counter value
    private var lastChangeCount: Int = 0
    
    /// Registered hotkey
    private var hotkeyRef: EventHotKeyRef?
    
    /// Registered event handlers
    private var eventHandler: EventHandlerRef?
    
    /// Event log for debugging
    private(set) var logs: [LogEntry] = []
    
    /// Is pasteboard initialized
    private var isPasteboardInitialized = false
    
    /// Is permissions granted (abbreviated from UserDefaults)
    private var permissionsGranted: Bool {
        get { UserDefaults.standard.bool(forKey: "ClipClap_PermissionsGranted") }
        set { UserDefaults.standard.set(newValue, forKey: "ClipClap_PermissionsGranted") }
    }
    
    /// Зберігає меню для правого кліку
    private var statusItemMenu: NSMenu?
    
    // MARK: - Initialization
    
    init() {
        log("Clipboard manager initialization")
        
        // Завантаження збережених налаштувань
        settings = ClipboardManagerSettings.loadFromUserDefaults()
        log("Settings loaded: maxItems=\(settings.maxHistoryItems), showStartupScreen=\(settings.showStartupScreen)")
        
        // Явне виведення налаштування showStartupScreen для дебагу
        print("DEBUG: showStartupScreen = \(settings.showStartupScreen)")
        log("DEBUG: showStartupScreen = \(settings.showStartupScreen)")
        
        // Check auto-launch status
        checkAutoLaunchStatus()
        
        // If first launch - enable auto-launch by default
        let firstLaunch = !UserDefaults.standard.bool(forKey: "ClipClap_HasLaunched")
        if firstLaunch {
            log("First launch - setting up auto-launch")
            UserDefaults.standard.set(true, forKey: "ClipClap_HasLaunched")
            toggleAutoLaunch(enabled: true)
        }
        
        // Setup UI elements
        setupStatusItem()
        setupPopover()
        
        // Launch the app in the most stable mode
        startApplicationWithCurrentPermissions()
        
        // Subscribe to settings changes
        setupNotifications()
        
        // Запускаємо таймер для автозбереження налаштувань
        settingsSaveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.settings.saveToUserDefaults()
            self?.log("Settings auto-saved")
        }
        
        // Automatically request permissions if not granted
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !AXIsProcessTrusted() {
                self.log("Automatic permissions request at startup")
                self.requestPermissions()
            }
        }
    }
    
    deinit {
        stopMonitoring()
        unregisterHotKey()
        settingsSaveTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        
        // Зберігаємо налаштування при знищенні об'єкта
        settings.saveToUserDefaults()
    }
    
    // MARK: - Public Methods
    
    /// Starts application with current permissions
    func startApplicationWithCurrentPermissions() {
        log("Starting the application")
        
        // Check permissions
        if AXIsProcessTrusted() {
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
    
    /// Shows popup with clipboard history
    func showPopover() {
        guard let button = statusItem?.button, 
              let popover = popover, 
              !popover.isShown else {
            return
        }
        
        log("Displaying clipboard history")
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    
    /// Closes popup with history
    func closePopover() {
        popover?.performClose(nil)
    }
    
    /// Запускає моніторинг буфера обміну з повною функціональністю
    func startMonitoring(force: Bool = false) {
        // Перенаправляємо на базовий моніторинг
        startBasicMonitoring(force: force)
    }
    
    /// Запускає базовий моніторинг без гарячих клавіш
    func startBasicMonitoring(force: Bool = false) {
        // Якщо моніторинг вже запущено і не потрібно примусово перезапускати
        if monitorTimer != nil && !force {
            log("Basic monitoring already started")
            return
        }
        
        log("Starting basic monitoring without hotkeys")
        
        // Зупиняємо попередній моніторинг
        stopMonitoring()
        
        // Ініціалізуємо буфер обміну, якщо ще не зроблено
        if !isPasteboardInitialized {
            initializePasteboard()
        }
        
        // Запускаємо таймер моніторингу
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    /// Зупиняє моніторинг буфера обміну
    func stopMonitoring() {
        if monitorTimer != nil {
            log("Stopping clipboard monitoring")
            monitorTimer?.invalidate()
            monitorTimer = nil
        }
    }
    
    /// Перевіряє статус дозволів і оновлює стан
    func checkPermissionsStatus() {
        let trusted = AXIsProcessTrusted()
        log("Checking permissions: \(trusted ? "granted" : "not granted")")
        
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
        
        // Перевіряємо статус дозволів через деякий час
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if AXIsProcessTrusted() {
                self.log("Permissions granted!")
                // Показуємо успішне повідомлення
                let successAlert = NSAlert()
                successAlert.messageText = "Permissions granted!"
                successAlert.informativeText = "Option+Command+V hotkeys are now active."
                successAlert.addButton(withTitle: "OK")
                successAlert.runModal()
                
                // Реєструємо гарячі клавіші
                self.registerHotKey()
            }
        }
    }
    
    /// Вставляє елемент з історії за індексом
    func pasteItemAtIndex(_ index: Int) {
        guard index >= 0 && index < clipboardHistory.count else {
            log("Error inserting: invalid index")
            return
        }
        
        let item = clipboardHistory[index]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Вставляємо елемент залежно від його типу
        switch item.type {
        case .text:
            if let text = item.textValue {
                pasteboard.setString(text, forType: .string)
                log("Inserted text: \(text.prefix(20))...")
            }
            
        case .image:
            if let image = item.imageValue {
                if let tiffData = image.tiffRepresentation {
                    pasteboard.setData(tiffData, forType: .tiff)
                    
                    // Додатково встановлюємо формат PNG для кращої сумісності
                    if let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                        pasteboard.setData(pngData, forType: .png)
                    }
                    
                    log("Inserted image")
                }
            }
            
        case .file:
            if let urls = item.fileURLs, !urls.isEmpty {
                // Перевірка, чи існують файли перед вставкою
                let existingFiles = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                
                if existingFiles.isEmpty {
                    log("Error: None of the files exist at their paths")
                    // Як запасний варіант, просто вставляємо шляхи як текст
                    let paths = urls.map { $0.path }.joined(separator: "\n")
                    pasteboard.setString(paths, forType: .string)
                    return
                }
                
                // Використовуємо кілька методів для забезпечення сумісності
                
                // 1. Основний метод для файлів
                let success1 = pasteboard.writeObjects(existingFiles as [NSURL])
                
                // 2. Альтернативний метод - встановлюємо як URL
                var success2 = false
                if existingFiles.count == 1, let urlData = try? NSKeyedArchiver.archivedData(withRootObject: existingFiles[0] as NSURL, requiringSecureCoding: false) {
                    pasteboard.setData(urlData, forType: .URL)
                    success2 = true
                }
                
                // 3. Встановлюємо fileURLs як спеціальний тип
                var success3 = false
                if let fileURLsData = try? NSKeyedArchiver.archivedData(withRootObject: existingFiles as NSArray, requiringSecureCoding: false) {
                    pasteboard.setData(fileURLsData, forType: .fileURL)
                    success3 = true
                }
                
                // Додатково додаємо як текстові шляхи для сумісності
                let paths = existingFiles.map { $0.path }.joined(separator: "\n")
                pasteboard.setString(paths, forType: .string)
                
                log("File insertion attempts: Primary=\(success1), URL=\(success2), FileURL=\(success3)")
                log("Inserted \(existingFiles.count) files")
                
                // Згенеруємо увесь вміст буфера для діагностики
                if let types = pasteboard.types {
                    log("Resulting clipboard types: \(types.map { $0.rawValue }.joined(separator: ", "))")
                }
            } else {
                log("Error: No valid files to insert")
            }
            
        case .unknown:
            log("Attempt to insert unknown data type")
            return
        }
        
        // Закриваємо попап
        closePopover()
    }
    
    /// Очищає історію буфера обміну
    func clearHistory() {
        clipboardHistory.removeAll()
        log("History cleared")
    }
    
    /// Перезапускає додаток для застосування дозволів
    func restartApplication() {
        log("Restarting application to apply changes")

        let alert = NSAlert()
        alert.messageText = "Restart application"
        alert.informativeText = "To apply the granted permissions, you need to restart ClipClap. Click 'Restart' to continue."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            // Отримуємо шлях до виконуваного файлу
            let executablePath = Bundle.main.executablePath!

            // Запускаємо процес перезапуску
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [executablePath]

            do {
                try task.run()
                // Завершуємо поточний додаток
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            } catch {
                log("ERROR: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Додає повідомлення в журнал
    private func log(_ message: String) {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timestamp = timeFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        
        // Створюємо запис з унікальним ідентифікатором
        let logEntry = LogEntry(message: logMessage)
        logs.append(logEntry)
        
        // Обмежуємо розмір журналу
        if logs.count > 100 {
            logs.removeFirst()
        }
        
        print(logMessage)
    }
    
    /// Налаштовує елемент в панелі меню
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else {
            log("Error creating menu bar button")
            return
        }
        
        button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard")
        
        // Резервний варіант, якщо іконка не завантажилась
        if button.image == nil {
            button.title = "📋"
        }
        
        // Створюємо меню для правого кліку
        let menu = NSMenu()
        
        // Пункт історії буфера обміну
        let historyItem = NSMenuItem(title: "Clipboard History", action: #selector(togglePopover(_:)), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Додаємо пункт налаштувань
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Пункт очищення історії
        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistoryAction(_:)), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Пункти перевірки та запиту дозволів
        let checkPermItem = NSMenuItem(title: "Check Permissions", action: #selector(checkPermissionsAction(_:)), keyEquivalent: "")
        checkPermItem.target = self
        menu.addItem(checkPermItem)
        
        let requestPermItem = NSMenuItem(title: "Request Permissions", action: #selector(requestPermissionsAction(_:)), keyEquivalent: "p")
        requestPermItem.target = self
        menu.addItem(requestPermItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Пункт виходу
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Налаштовуємо обробник кліків
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        // Обробник кліків для різних типів кнопок миші
        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
        
        // Зберігаємо меню для використання при правому кліку
        self.statusItemMenu = menu
    }
    
    /// Налаштовує попап для відображення історії
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 450)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ClipboardHistoryView(clipboardManager: self))
        
        // Закриваємо попап при кліку поза ним
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover?.isShown == true {
                self.closePopover()
            }
        }
    }
    
    /// Ініціалізує буфер обміну
    private func initializePasteboard() {
        // Додаємо додаткові перехоплення помилок
        do {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            
            // Максимальний набір типів для підтримки
            let pasteboardTypes: [NSPasteboard.PasteboardType] = [
                .string, .rtf, .rtfd, .tiff, .png, .pdf, .fileURL, .URL,
                NSPasteboard.PasteboardType("public.file-url"),
                NSPasteboard.PasteboardType("com.apple.finder.file")
            ]
            
            // Реєструємо типи даних
            pasteboard.declareTypes(pasteboardTypes, owner: nil)
            
            // Запам'ятовуємо початковий стан лічильника змін
            lastChangeCount = pasteboard.changeCount
            isPasteboardInitialized = true
            
            log("Clipboard initialized (ID: \(pasteboard.changeCount))")
        } catch {
            log("Error initializing clipboard: \(error.localizedDescription)")
        }
    }
    
    /// Перевіряє зміни в буфері обміну
    private func checkClipboard() {
        // Перевіряємо наявність доступу до буфера обміну перед роботою
        guard isPasteboardInitialized else {
            log("Clipboard not initialized")
            initializePasteboard()
            return
        }
        
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        // Перевіряємо, чи змінився буфер обміну
        guard currentChangeCount != lastChangeCount else {
            return
        }
        
        // Оновлюємо лічильник змін
        lastChangeCount = currentChangeCount
        
        // Логуємо доступні типи даних для діагностики
        let availableTypes = pasteboard.types ?? []
        log("Clipboard types: \(availableTypes.map { $0.rawValue }.joined(separator: ", "))")
        
        // Спочатку перевіряємо, чи є файли в буфері обміну
        // Спроба отримати файли (з вищим пріоритетом)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            log("Detected files in clipboard: \(fileURLs.count) files")
            // Виводимо шляхи для діагностики
            for (index, url) in fileURLs.enumerated() {
                log("File \(index): \(url.path) (exists: \(FileManager.default.fileExists(atPath: url.path)))")
            }
            addNewItem(ClipboardItem(fileURLs: fileURLs))
            return
        }
        
        // Перевіряємо формати зображень у правильному порядку
        // Спочатку перевіряємо PNG як найкращий формат для якості
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            log("Detected image in clipboard (NSImage)")
            addNewItem(ClipboardItem(image: image))
            return
        }
        
        // Якщо не вдалося як NSImage, спробуємо конкретні типи
        if let pngData = pasteboard.data(forType: .png), 
           let image = NSImage(data: pngData) {
            log("Detected PNG image in clipboard")
            addNewItem(ClipboardItem(image: image))
            return
        }
        
        // Перевіряємо TIFF формат
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            log("Detected TIFF image in clipboard")
            addNewItem(ClipboardItem(image: image))
            return
        }
        
        // Спроба отримати текст (найнижчий пріоритет)
        if let clipboardString = pasteboard.string(forType: .string) {
            // Перевіряємо, чи це не пустий текст
            if !clipboardString.isEmpty {
                log("Detected text in clipboard")
                addNewItem(ClipboardItem(text: clipboardString))
                return
            }
        }
        
        log("Received clipboard change, but failed to recognize data type")
    }
    
    /// Додає новий елемент в історію
    private func addNewItem(_ item: ClipboardItem) {
        // Перевіряємо, чи це не дублікат останнього елемента
        if let lastItem = clipboardHistory.first {
            // Порівнюємо елементи залежно від їх типу
            if lastItem.type == item.type {
                switch item.type {
                case .text:
                    if lastItem.textValue == item.textValue {
                        return
                    }
                case .image:
                    // Просте порівняння розмірів зображень як ознака ідентичності
                    if let lastImage = lastItem.imageValue, let newImage = item.imageValue,
                       lastImage.size == newImage.size {
                        return
                    }
                case .file:
                    if lastItem.fileURLs == item.fileURLs {
                        return
                    }
                case .unknown:
                    return
                }
            }
        }
        
        // Додаємо новий елемент на початок історії
        clipboardHistory.insert(item, at: 0)
        
        // Логуємо додавання нового елемента
        switch item.type {
        case .text:
            if let text = item.textValue {
                log("Added new text: \(text.prefix(20))...")
            }
        case .image:
            log("Added new image")
        case .file:
            if let urls = item.fileURLs {
                log("Added file(s): \(urls.count) items")
            }
        case .unknown:
            log("Added unknown type element")
        }
        
        // Обмежуємо розмір історії
        if clipboardHistory.count > settings.maxHistoryItems {
            clipboardHistory.removeLast()
        }
    }
    
    /// Реєструє гарячу клавішу для доступу до історії
    private func registerHotKey() {
        // Спочатку видаляємо усі попередні обробники
        unregisterHotKey()
        
        if AXIsProcessTrusted() {
            // Якщо є дозволи - реєструємо глобальний обробник
            log("HOTKEY REGISTERED")
            
            // Додаємо локальний обробник для поглинання події
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                
                // Перевіряємо Option+Command+V
                if event.modifierFlags.contains([.command, .option]) && 
                   event.keyCode == 9 /* V */ {
                    DispatchQueue.main.async {
                        self.showPopover()
                    }
                    return nil // поглинаємо подію, щоб вона не передавалась далі системі
                }
                return event
            }
            
            // Глобальний обробник для інших додатків
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return }
                
                // Перевіряємо Option+Command+V
                if event.modifierFlags.contains([.command, .option]) && 
                   event.keyCode == 9 /* V */ {
                    DispatchQueue.main.async {
                        self.showPopover()
                    }
                }
            }
        } else {
            // Якщо немає дозволів - використовуємо локальний обробник
            log("HOTKEY REGISTERED")
            
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                
                // Перевіряємо Option+Command+V
                if event.modifierFlags.contains([.command, .option]) && 
                   event.keyCode == 9 /* V */ {
                    DispatchQueue.main.async {
                        self.showPopover()
                    }
                    return nil // поглинаємо подію
                }
                return event
            }
            
            // Також реєструємо гарячу клавішу в меню
            if let menu = statusItem?.menu {
                let item = NSMenuItem(title: "Show Clipboard History", action: #selector(togglePopover(_:)), keyEquivalent: "v")
                item.keyEquivalentModifierMask = [.command, .option]
                menu.insertItem(item, at: 0)
            }
        }
        
        log("HOTKEY REGISTERED")
    }
    
    /// Скасовує реєстрацію гарячої клавіші
    private func unregisterHotKey() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
            log("HOTKEY UNREGISTERED")
        }
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
    }
    
    /// Відкриває системні налаштування Доступності
    func openSystemPreferencesAccessibility() {
        log("Opening system accessibility settings")
        
        // Визначаємо URL залежно від версії macOS
        var preferencesURL: URL
        
        if #available(macOS 13.0, *) {
            // macOS 13 (Ventura) і новіші
            preferencesURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        } else if #available(macOS 12.0, *) {
            // macOS 12 (Monterey)
            preferencesURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        } else {
            // Старіші версії
            preferencesURL = URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane")
        }
        
        // Відкриваємо налаштування
        NSWorkspace.shared.open(preferencesURL)
    }
    
    /// Перевіряє статус автозапуску
    private func checkAutoLaunchStatus() {
        if #available(macOS 13.0, *) {
            // Використовуємо новий API для macOS 13+
            let service = SMAppService.mainApp
            isAutoLaunchEnabled = service.status == .enabled
            log("AUTOLAUNCH STATUS: \(isAutoLaunchEnabled ? "ENABLED" : "DISABLED")")
        } else {
            // Для старіших версій використовуємо LSSharedFileList
            let bundleId = Bundle.main.bundleIdentifier ?? "com.example.ClipClap"
            
            if let loginItemsRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil) {
                let loginItems = loginItemsRef.takeRetainedValue()
                
                if let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] {
                    let bundleURL = Bundle.main.bundleURL
                    
                    for loginItem in loginItemsSnapshot {
                        if let itemURL = LSSharedFileListItemCopyResolvedURL(loginItem, 0, nil)?.takeRetainedValue() as URL? {
                            if itemURL.path == bundleURL.path {
                                isAutoLaunchEnabled = true
                                break
                            }
                        }
                    }
                }
            }
            
            log("AUTOLAUNCH STATUS: \(isAutoLaunchEnabled ? "ENABLED" : "DISABLED")")
        }
    }
    
    /// Вмикає або вимикає автозапуск
    func toggleAutoLaunch(enabled: Bool) {
        if #available(macOS 13.0, *) {
            // Використовуємо новий API для macOS 13+
            let service = SMAppService.mainApp
            
            do {
                if enabled {
                    if service.status != .enabled {
                        try service.register()
                        log("AUTOLAUNCH ENABLED")
                    }
                } else {
                    if service.status == .enabled {
                        try service.unregister()
                        log("AUTOLAUNCH DISABLED")
                    }
                }
                
                // Оновлюємо статус після зміни
                isAutoLaunchEnabled = service.status == .enabled
            } catch {
                log("ERROR: \(error.localizedDescription)")
            }
        } else {
            // Для старіших версій використовуємо LSSharedFileList
            if let loginItemsRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil) {
                let loginItems = loginItemsRef.takeRetainedValue()
                
                if enabled {
                    // Додаємо програму до списку автозапуску
                    let bundleURL = Bundle.main.bundleURL as CFURL
                    LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemLast.takeRetainedValue(), nil, nil, bundleURL, nil, nil)
                    log("AUTOLAUNCH ENABLED")
                } else {
                    // Видаляємо програму зі списку автозапуску
                    if let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] {
                        let bundleURL = Bundle.main.bundleURL
                        
                        for loginItem in loginItemsSnapshot {
                            if let itemURL = LSSharedFileListItemCopyResolvedURL(loginItem, 0, nil)?.takeRetainedValue() as URL? {
                                if itemURL.path == bundleURL.path {
                                    LSSharedFileListItemRemove(loginItems, loginItem)
                                    break
                                }
                            }
                        }
                    }
                    log("AUTOLAUNCH DISABLED")
                }
            } else {
                log("ERROR: Failed to create login items list")
            }
            
            // Оновлюємо статус після зміни
            checkAutoLaunchStatus() // Перевіряємо актуальний стан замість присвоєння
        }
    }
    
    // MARK: - Event Handlers
    
    /// Shows settings window
    @objc private func showSettings(_ sender: Any?) {
        // Create and show settings window
        let settingsWindowController = NSWindowController(
            window: NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
        )
        
        settingsWindowController.window?.title = "Settings"
        settingsWindowController.window?.center()
        
        let settingsView = SettingsView()
            .environmentObject(self)
        
        settingsWindowController.window?.contentView = NSHostingView(rootView: settingsView)
        settingsWindowController.showWindow(nil)
        
        // Make window active
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Обробляє клік на іконці в треї, розрізняючи лівий і правий кліки
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            // Правий клік - показуємо меню
            if let menu = statusItemMenu, let event = event {
                NSMenu.popUpContextMenu(menu, with: event, for: sender)
            }
        } else {
            // Лівий клік - показуємо історію
            showPopover()
        }
    }
    
    /// Обробляє натискання на іконку в панелі меню
    @objc private func togglePopover(_ sender: Any?) {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    /// Обробляє очищення історії з меню
    @objc private func clearHistoryAction(_ sender: Any?) {
        clearHistory()
    }
    
    /// Обробляє запит дозволів з меню
    @objc private func requestPermissionsAction(_ sender: Any?) {
        requestPermissions()
    }
    
    /// Обробляє перевірку дозволів
    @objc private func checkPermissionsAction(_ sender: Any?) {
        checkPermissionsStatus()
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            if AXIsProcessTrusted() {
                alert.messageText = "Permissions Granted"
                alert.informativeText = "The app has all the necessary permissions for full functionality."
            } else {
                alert.messageText = "Permissions Not Granted"
                alert.informativeText = "The app is running in limited mode. Grant accessibility permissions for full functionality."
            }
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    /// Обробляє вихід з програми
    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
    
    /// Обробляє завершення програми
    @objc private func applicationWillTerminate() {
        // Зберігаємо налаштування перед завершенням
        settings.saveToUserDefaults()
        log("Settings saved on application termination")
        
        stopMonitoring()
        unregisterHotKey()
    }
    
    /// Обробляє активацію програми
    @objc private func applicationDidBecomeActive() {
        // При активації перевіряємо статус дозволів
        checkPermissionsStatus()
    }
    
    // MARK: - Additional code for avoiding showing main window
    
    // Add property for storing reference to main window
    private var mainWindowController: NSWindowController?
    
    // Method for setting up main window (which we won't show)
    func setupMainWindow() {
        // Create window but don't show it
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        
        mainWindow.title = "ClipClap"
        mainWindow.center()
        
        let contentView = ContentView()
            .environmentObject(self)
        
        mainWindow.contentView = NSHostingView(rootView: contentView)
        
        // Store reference to window controller
        mainWindowController = NSWindowController(window: mainWindow)
        
        // Show the window if enabled in settings
        if settings.showStartupScreen {
            log("Showing startup window (showStartupScreen=true)")
            mainWindowController?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            log("Hiding startup window (showStartupScreen=false)")
        }
    }
    
    // Method for displaying main window if needed
    func showMainWindow() {
        if mainWindowController == nil {
            setupMainWindow()
        }
        
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Log Entry Structure

/// Structure for storing log entry with unique ID
struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let timestamp = Date()
}

// MARK: - Helper Structures

/// Clipboard manager state
enum ClipboardManagerState: Equatable {
    case initializing
    case ready
    case needsPermissions
    case error(String)
    
    static func == (lhs: ClipboardManagerState, rhs: ClipboardManagerState) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing):
            return true
        case (.ready, .ready):
            return true
        case (.needsPermissions, .needsPermissions):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

/// Clipboard manager settings
struct ClipboardManagerSettings {
    /// Maximum number of items in history
    var maxHistoryItems: Int = 50
    
    /// Auto-launch application (enabled by default)
    var autoLaunchEnabled: Bool = true
    
    /// Show startup screen when application launches
    var showStartupScreen: Bool = true
    
    /// Saves settings to UserDefaults
    func saveToUserDefaults() {
        UserDefaults.standard.set(maxHistoryItems, forKey: "ClipClap_MaxHistoryItems")
        UserDefaults.standard.set(autoLaunchEnabled, forKey: "ClipClap_AutoLaunchEnabled")
        UserDefaults.standard.set(showStartupScreen, forKey: "ClipClap_ShowStartupScreen")
    }
    
    /// Loads settings from UserDefaults
    static func loadFromUserDefaults() -> ClipboardManagerSettings {
        var settings = ClipboardManagerSettings()
        
        if UserDefaults.standard.object(forKey: "ClipClap_MaxHistoryItems") != nil {
            settings.maxHistoryItems = UserDefaults.standard.integer(forKey: "ClipClap_MaxHistoryItems")
        }
        
        if UserDefaults.standard.object(forKey: "ClipClap_ShowStartupScreen") != nil {
            settings.showStartupScreen = UserDefaults.standard.bool(forKey: "ClipClap_ShowStartupScreen")
        }
        
        // AutoLaunch налаштування керується окремо через API системи
        return settings
    }
}

// Delete duplicate ClipboardHistoryView and ClipboardItemView, they're now in ClipboardHistoryView.swift






