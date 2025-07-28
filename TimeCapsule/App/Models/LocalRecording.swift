import Foundation

struct LocalRecording: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let duration: TimeInterval
    let fileSize: Int64
    let createdAt: Date
    
    var filename: String {
        url.lastPathComponent
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var formattedCreatedAt: String {
        DateFormatter.displayFormatter.string(from: createdAt)
    }
    
    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

private extension DateFormatter {
    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}