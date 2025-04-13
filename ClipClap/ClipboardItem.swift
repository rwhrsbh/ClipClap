import Cocoa

/// Clipboard item types
enum ClipboardItemType {
    case text
    case image
    case file
    case unknown
}

/// Model for storing clipboard items
class ClipboardItem: Identifiable {
    let id = UUID()
    let type: ClipboardItemType
    let timestamp: Date
    let textValue: String?
    let imageValue: NSImage?
    let fileURLs: [URL]?
    
    var preview: String {
        switch type {
        case .text:
            guard let text = textValue else { return "Empty text" }
            return text.count > 50 ? String(text.prefix(50)) + "..." : text
        case .image:
            return "Image"
        case .file:
            if let urls = fileURLs, let firstURL = urls.first {
                return urls.count > 1 
                    ? "\(firstURL.lastPathComponent) and \(urls.count - 1) more file(s)" 
                    : firstURL.lastPathComponent
            }
            return "File"
        case .unknown:
            return "Unknown format"
        }
    }
    
    /// Initializer for text data
    init(text: String) {
        self.type = .text
        self.textValue = text
        self.imageValue = nil
        self.fileURLs = nil
        self.timestamp = Date()
    }
    
    /// Initializer for images
    init(image: NSImage) {
        self.type = .image
        self.textValue = nil
        self.imageValue = image
        self.fileURLs = nil
        self.timestamp = Date()
    }
    
    /// Initializer for files
    init(fileURLs: [URL]) {
        self.type = .file
        self.textValue = nil
        self.imageValue = nil
        self.fileURLs = fileURLs
        self.timestamp = Date()
    }
    
    /// Initializer for unknown type
    init() {
        self.type = .unknown
        self.textValue = nil
        self.imageValue = nil
        self.fileURLs = nil
        self.timestamp = Date()
    }
}
