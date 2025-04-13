import SwiftUI

/// Interface for displaying clipboard history
struct ClipboardHistoryView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    
    var body: some View {
        VStack {
            // Header
            HStack {
                Text("Clipboard History")
                    .font(.headline)
                Spacer()
                Button(action: {
                    clipboardManager.clearHistory()
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear History")
            }
            .padding([.horizontal, .top])
            
            // List of history items
            List {
                if clipboardManager.clipboardHistory.isEmpty {
                    Text("History is empty")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(0..<clipboardManager.clipboardHistory.count, id: \.self) { index in
                        ClipboardItemView(item: clipboardManager.clipboardHistory[index])
                            .onTapGesture {
                                clipboardManager.pasteItemAtIndex(index)
                            }
                    }
                }
            }
            
            // Information about operation
            HStack {
                Image(systemName: "info.circle")
                Text("Click on an item to copy")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 5)
        }
        .frame(width: 320, height: 450)
    }
}

/// Representation of individual history item
struct ClipboardItemView: View {
    let item: ClipboardItem
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Icon of item type
            Image(systemName: iconName)
                .frame(width: 20)
            
            // Item content
            VStack(alignment: .leading) {
                if item.type == .text, let text = item.textValue {
                    Text(text.replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else if item.type == .image, let image = item.imageValue {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 60)
                } else if item.type == .file, let urls = item.fileURLs {
                    VStack(alignment: .leading) {
                        Text(urls.first?.lastPathComponent ?? "File")
                            .lineLimit(1)
                        if urls.count > 1 {
                            Text("and \(urls.count - 1) more file(s)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text(item.preview)
                }
                
                // Creation time
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Paste button
            Image(systemName: "arrow.right.doc.on.clipboard")
                .foregroundColor(.accentColor)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
    
    // Defines icon based on item type
    private var iconName: String {
        switch item.type {
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .file:
            return "folder"
        case .unknown:
            return "questionmark.square"
        }
    }
    
    // Formats creation time of item
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: item.timestamp)
    }
} 