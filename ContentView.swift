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
            
            if !clipboardManager.isAccessibilityPermissionGranted {
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

// Hotkeys
            VStack(alignment: .leading, spacing: 15) {
                Text("How to use:")
                    .font(.headline)
                
                if clipboardManager.isAccessibilityPermissionGranted {
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
            }

// Action buttons
            HStack {
                Spacer()
                
                if !clipboardManager.isAccessibilityPermissionGranted {
                    Button(action: {
                        clipboardManager.requestPermissions()
                    }) {
                        Label("Grant Permissions", systemImage: "lock.shield")
                    }
                    
                    Spacer()
                }
            } 

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var showSettings = false
    @State private var permissionCheckTimer: Timer?
    
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
            
            // Решта View залишається без змін...
        }
        .padding()
        .frame(width: 500, height: 600)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(clipboardManager)
        }
        .onAppear {
            // Перевіряємо дозволи при появі вікна
            clipboardManager.checkPermissionsStatus()
            
            // Встановлюємо таймер для періодичної перевірки дозволів
            permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                clipboardManager.checkPermissionsStatus()
            }
        }
        .onDisappear {
            // Очищаємо таймер при зникненні вікна
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }
} 