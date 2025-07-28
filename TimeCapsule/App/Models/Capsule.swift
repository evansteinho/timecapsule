import Foundation

struct Capsule: Identifiable, Codable {
    let id: String
    let userId: String
    let audioURL: URL?
    let transcription: String?
    let duration: TimeInterval
    let fileSize: Int64
    let createdAt: Date
    let updatedAt: Date
    let status: CapsuleStatus
    let metadata: CapsuleMetadata?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case audioURL = "audio_url"
        case transcription
        case duration
        case fileSize = "file_size"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case metadata
    }
}

enum CapsuleStatus: String, Codable, CaseIterable {
    case uploading
    case processing
    case transcribing
    case completed
    case failed
    
    var displayName: String {
        switch self {
        case .uploading:
            return "Uploading"
        case .processing:
            return "Processing"
        case .transcribing:
            return "Transcribing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .uploading, .processing, .transcribing:
            return true
        case .completed, .failed:
            return false
        }
    }
}

struct CapsuleMetadata: Codable {
    let emotions: [EmotionScore]?
    let topics: [String]?
    let summary: String?
    
    enum CodingKeys: String, CodingKey {
        case emotions
        case topics
        case summary
    }
}

struct EmotionScore: Codable {
    let emotion: String
    let score: Double
    let confidence: Double
}

struct CapsuleUploadResponse: Codable {
    let capsule: Capsule
    let uploadURL: URL?
    
    enum CodingKeys: String, CodingKey {
        case capsule
        case uploadURL = "upload_url"
    }
}