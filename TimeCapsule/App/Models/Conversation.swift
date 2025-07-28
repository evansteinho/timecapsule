import Foundation

// MARK: - Conversation Models

struct Conversation: Identifiable, Codable {
    let id: String
    let userId: String
    let capsuleId: String
    let messages: [ConversationMessage]
    let createdAt: Date
    let updatedAt: Date
    let status: ConversationStatus
    let metadata: ConversationMetadata?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case capsuleId = "capsule_id"
        case messages
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case metadata
    }
}

enum ConversationStatus: String, Codable, CaseIterable {
    case active
    case paused
    case completed
    case timeLocked = "time_locked"
    
    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        case .completed:
            return "Completed"
        case .timeLocked:
            return "Time Locked"
        }
    }
}

struct ConversationMessage: Identifiable, Codable {
    let id: String
    let conversationId: String
    let content: String
    let role: MessageRole
    let audioURL: URL?
    let timestamp: Date
    let metadata: MessageMetadata?
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case content
        case role
        case audioURL = "audio_url"
        case timestamp
        case metadata
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant = "past_self"
    
    var displayName: String {
        switch self {
        case .user:
            return "You"
        case .assistant:
            return "Past Self"
        }
    }
}

struct MessageMetadata: Codable {
    let emotion: String?
    let confidence: Double?
    let processingTime: TimeInterval?
    let voiceCloneUsed: Bool?
    
    enum CodingKeys: String, CodingKey {
        case emotion
        case confidence
        case processingTime = "processing_time"
        case voiceCloneUsed = "voice_clone_used"
    }
}

struct ConversationMetadata: Codable {
    let totalMessages: Int
    let averageResponseTime: TimeInterval?
    let dominantEmotion: String?
    let topicsDiscussed: [String]?
    let timeLockUntil: Date?
    
    enum CodingKeys: String, CodingKey {
        case totalMessages = "total_messages"
        case averageResponseTime = "average_response_time"
        case dominantEmotion = "dominant_emotion"
        case topicsDiscussed = "topics_discussed"
        case timeLockUntil = "time_lock_until"
    }
}

// MARK: - API Request/Response Models

struct StartConversationRequest: Codable {
    let capsuleId: String
    let initialMessage: String?
    let voiceCloneEnabled: Bool
    
    enum CodingKeys: String, CodingKey {
        case capsuleId = "capsule_id"
        case initialMessage = "initial_message"
        case voiceCloneEnabled = "voice_clone_enabled"
    }
}

struct StartConversationResponse: Codable {
    let conversation: Conversation
    let initialResponse: ConversationMessage?
    let timeLockInfo: TimeLockInfo?
    
    enum CodingKeys: String, CodingKey {
        case conversation
        case initialResponse = "initial_response"
        case timeLockInfo = "time_lock_info"
    }
}

struct SendMessageRequest: Codable {
    let conversationId: String
    let content: String
    let requestAudio: Bool
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case content
        case requestAudio = "request_audio"
    }
}

struct SendMessageResponse: Codable {
    let message: ConversationMessage
    let audioStreamURL: URL?
    let isTimeLocked: Bool
    
    enum CodingKeys: String, CodingKey {
        case message
        case audioStreamURL = "audio_stream_url"
        case isTimeLocked = "is_time_locked"
    }
}

struct TimeLockInfo: Codable {
    let isLocked: Bool
    let unlockTime: Date?
    let lockReason: String?
    let remainingTime: TimeInterval?
    
    enum CodingKeys: String, CodingKey {
        case isLocked = "is_locked"
        case unlockTime = "unlock_time"
        case lockReason = "lock_reason"
        case remainingTime = "remaining_time"
    }
    
    var isCurrentlyLocked: Bool {
        guard isLocked, let unlockTime = unlockTime else { return false }
        return Date() < unlockTime
    }
    
    var timeUntilUnlock: TimeInterval? {
        guard let unlockTime = unlockTime else { return nil }
        let remaining = unlockTime.timeIntervalSince(Date())
        return remaining > 0 ? remaining : nil
    }
}

// MARK: - Local Conversation State

struct LocalConversationState {
    var isTyping: Bool = false
    var isGeneratingAudio: Bool = false
    var isPlayingAudio: Bool = false
    var currentlyPlayingMessageId: String?
    var scrollToMessageId: String?
    var errorMessage: String?
}

// MARK: - Conversation Context

struct ConversationContext: Codable {
    let relevantCapsules: [ContextCapsule]
    let userProfile: UserProfile?
    let timeContext: TimeContext
    let emotionalContext: EmotionalContext?
    
    enum CodingKeys: String, CodingKey {
        case relevantCapsules = "relevant_capsules"
        case userProfile = "user_profile"
        case timeContext = "time_context"
        case emotionalContext = "emotional_context"
    }
}

struct ContextCapsule: Codable {
    let id: String
    let transcription: String
    let createdAt: Date
    let relevanceScore: Double
    let emotions: [EmotionScore]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case transcription
        case createdAt = "created_at"
        case relevanceScore = "relevance_score"
        case emotions
    }
}

struct UserProfile: Codable {
    let preferredTopics: [String]?
    let communicationStyle: String?
    let timeZone: String?
    let personalityInsights: [String: Double]?
    
    enum CodingKeys: String, CodingKey {
        case preferredTopics = "preferred_topics"
        case communicationStyle = "communication_style"
        case timeZone = "time_zone"
        case personalityInsights = "personality_insights"
    }
}

struct TimeContext: Codable {
    let currentTime: Date
    let timeSinceLastCapsule: TimeInterval?
    let timeOfDay: String
    let dayOfWeek: String
    
    enum CodingKeys: String, CodingKey {
        case currentTime = "current_time"
        case timeSinceLastCapsule = "time_since_last_capsule"
        case timeOfDay = "time_of_day"
        case dayOfWeek = "day_of_week"
    }
}

struct EmotionalContext: Codable {
    let recentEmotions: [EmotionScore]
    let emotionalTrend: String?
    let moodStability: Double?
    
    enum CodingKeys: String, CodingKey {
        case recentEmotions = "recent_emotions"
        case emotionalTrend = "emotional_trend"
        case moodStability = "mood_stability"
    }
}