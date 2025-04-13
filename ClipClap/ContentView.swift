import SwiftUI

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "clipboard")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                Text("ClipClap")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            
            // Description
            Text("Modern clipboard manager for macOS")
                .font(.headline)
                .foregroundColor(.secondary)
            
            // Status
            statusView
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
            
            // Hotkeys
            VStack(alignment: .leading, spacing: 15) {
                Text("How to use:")
                    .font(.headline)
                
                if AXIsProcessTrusted() {
                    HStack {
                        Image(systemName: "command")
                        Image(systemName: "shift")
                        Text("V")
                        Text("—")
                        Text("Show clipboard history")
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Hotkeys are not available")
                            .foregroundColor(.orange)
                    }
                    
                    Button("Grant permissions for hotkeys") {
                        clipboardManager.requestPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.white)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                
                HStack {
                    Image(systemName: "cursorarrow.click.2")
                    Text("—")
                    Text("Click on the icon in the menu bar")
                }
                
                HStack {
                    Image(systemName: "cursorarrow.click.2")
                    Text("—")
                    Text("Select an item from the list to copy")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
            
            // Log
            if !clipboardManager.logs.isEmpty {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Log:")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: {
                            showSettings.toggle()
                        }) {
                            Image(systemName: "gear")
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(clipboardManager.logs) { logEntry in
                                Text(logEntry.message)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
            }
            
            Spacer()
            
            // Action buttons
            HStack {
                Spacer()
                
                if !AXIsProcessTrusted() {
                    Button(action: {
                        clipboardManager.requestPermissions()
                    }) {
                        Label("Grant Permissions", systemImage: "lock.shield")
                    }
                    
                    Spacer()
                }
                
                Button(action: {
                    clipboardManager.showPopover()
                }) {
                    Label("Show History", systemImage: "list.bullet")
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
        }
        .padding()
        .frame(width: 500, height: 700)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(clipboardManager)
        }
        .onAppear {
            clipboardManager.checkPermissionsStatus()
        }
    }
    
    // Status view
    var statusView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("App Status:")
                    .font(.headline)
                
                Spacer()
                
                statusBadge
            }
            
            Text("Items in history: \(clipboardManager.clipboardHistory.count)")
                .font(.subheadline)
            
            if !AXIsProcessTrusted() {
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundColor(.orange)
                    Text("Hotkeys are not available")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 5)
            }
        }
    }
    
    // Status badge
    var statusBadge: some View {
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
            
            Text("Active")
                .font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
    }
}

// Settings view
struct SettingsView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var maxHistoryItems: Double
    @State private var autoLaunchEnabled: Bool
    @State private var showStartupScreen: Bool
    
    init() {
        // Initialize with default values
        _maxHistoryItems = State(initialValue: Double(50))
        _autoLaunchEnabled = State(initialValue: true)
        _showStartupScreen = State(initialValue: true)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.largeTitle)
                .padding(.bottom)
            
            VStack(alignment: .leading) {
                Text("Maximum number of history items: \(Int(maxHistoryItems))")
                
                Slider(value: $maxHistoryItems, in: 10...200, step: 10)
            }
            .padding()
            
            Toggle("Launch at login", isOn: $autoLaunchEnabled)
                .padding()
                .onChange(of: autoLaunchEnabled) { newValue in
                    clipboardManager.toggleAutoLaunch(enabled: newValue)
                }
                
            Toggle("Show startup screen", isOn: $showStartupScreen)
                .padding()
                .onChange(of: showStartupScreen) { newValue in
                    // Для наочності - при зміні опції відразу показуємо ефект
                    print("Changed showStartupScreen to: \(newValue)")
                }
            
            Spacer()
            
            Button("Save Settings") {
                // Save settings
                clipboardManager.settings.maxHistoryItems = Int(maxHistoryItems)
                clipboardManager.settings.autoLaunchEnabled = autoLaunchEnabled
                clipboardManager.settings.showStartupScreen = showStartupScreen
                
                // Зберігаємо налаштування в UserDefaults
                clipboardManager.settings.saveToUserDefaults()
                
                // Close window
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .padding()
        .frame(width: 450, height: 400)
        .onAppear {
            // Load current settings
            maxHistoryItems = Double(clipboardManager.settings.maxHistoryItems)
            autoLaunchEnabled = clipboardManager.isAutoLaunchEnabled
            showStartupScreen = clipboardManager.settings.showStartupScreen
            
            print("Loaded settings: showStartupScreen=\(showStartupScreen)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ClipboardManager())
    }
}
