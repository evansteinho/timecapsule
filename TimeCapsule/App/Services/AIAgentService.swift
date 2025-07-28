import Foundation
import Combine
import AVFoundation

protocol AIAgentServiceProtocol {
    func startConversation(with capsule: Capsule, initialMessage: String?) async throws -> StartConversationResponse
    func sendMessage(_ content: String, to conversationId: String, requestAudio: Bool) async throws -> SendMessageResponse
    func getConversation(id: String) async throws -> Conversation
    func streamAudioResponse(from url: URL) -> AsyncThrowingStream<Data, Error>
    func checkTimeLock(for conversationId: String) async throws -> TimeLockInfo
}

final class AIAgentService: AIAgentServiceProtocol {
    private let networkService: NetworkServiceProtocol
    private let capsuleService: CapsuleServiceProtocol
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Audio streaming
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    
    init(
        networkService: NetworkServiceProtocol = NetworkService(),
        capsuleService: CapsuleServiceProtocol = CapsuleService()
    ) {
        self.networkService = networkService
        self.capsuleService = capsuleService
        setupAudioSession()
    }
    
    // MARK: - Conversation Management
    
    func startConversation(with capsule: Capsule, initialMessage: String?) async throws -> StartConversationResponse {
        let context = try await buildConversationContext(for: capsule)
        
        let request = StartConversationRequest(
            capsuleId: capsule.id,
            initialMessage: initialMessage,
            voiceCloneEnabled: true
        )
        
        let requestBody: [String: Any] = [
            "capsule_id": request.capsuleId,
            "initial_message": request.initialMessage ?? "",
            "voice_clone_enabled": request.voiceCloneEnabled,
            "context": try encodeContext(context)
        ]
        
        let response: StartConversationResponse = try await networkService.post(
            path: "/v0/conversation/start",
            body: requestBody
        )
        
        return response
    }
    
    func sendMessage(_ content: String, to conversationId: String, requestAudio: Bool = true) async throws -> SendMessageResponse {
        let request = SendMessageRequest(
            conversationId: conversationId,
            content: content,
            requestAudio: requestAudio
        )
        
        let requestBody: [String: Any] = [
            "conversation_id": request.conversationId,
            "content": request.content,
            "request_audio": request.requestAudio
        ]
        
        let response: SendMessageResponse = try await networkService.post(
            path: "/v0/conversation/message",
            body: requestBody
        )
        
        return response
    }
    
    func getConversation(id: String) async throws -> Conversation {
        return try await networkService.get(path: "/v0/conversation/\(id)")
    }
    
    func checkTimeLock(for conversationId: String) async throws -> TimeLockInfo {
        return try await networkService.get(path: "/v0/conversation/\(conversationId)/timelock")
    }
    
    // MARK: - Context Building
    
    private func buildConversationContext(for capsule: Capsule) async throws -> ConversationContext {
        // Get all user's capsules for context
        let allCapsules = try await capsuleService.getAllCapsules()
        
        // Find relevant capsules using semantic similarity (simplified)
        let relevantCapsules = findRelevantCapsules(
            for: capsule,
            from: allCapsules
        )
        
        let timeContext = buildTimeContext(for: capsule)
        let emotionalContext = buildEmotionalContext(from: allCapsules)
        
        return ConversationContext(
            relevantCapsules: relevantCapsules,
            userProfile: nil, // TODO: Implement user profiling
            timeContext: timeContext,
            emotionalContext: emotionalContext
        )
    }
    
    private func findRelevantCapsules(for targetCapsule: Capsule, from allCapsules: [Capsule]) -> [ContextCapsule] {
        // Simple relevance algorithm - in production, use vector similarity
        let completedCapsules = allCapsules.filter { $0.status == .completed && $0.id != targetCapsule.id }
        
        return completedCapsules
            .prefix(5) // Limit to 5 most relevant
            .map { capsule in
                let relevanceScore = calculateRelevanceScore(capsule, to: targetCapsule)
                return ContextCapsule(
                    id: capsule.id,
                    transcription: capsule.transcription ?? "",
                    createdAt: capsule.createdAt,
                    relevanceScore: relevanceScore,
                    emotions: capsule.metadata?.emotions
                )
            }
            .sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    private func calculateRelevanceScore(_ capsule: Capsule, to target: Capsule) -> Double {
        // Simplified relevance scoring
        var score = 0.0
        
        // Time proximity (more recent = more relevant)
        let daysDifference = abs(capsule.createdAt.timeIntervalSince(target.createdAt)) / (24 * 3600)
        score += max(0, 1.0 - (daysDifference / 365)) * 0.3
        
        // Emotional similarity
        if let capsuleEmotions = capsule.metadata?.emotions,
           let targetEmotions = target.metadata?.emotions {
            let emotionalSimilarity = calculateEmotionalSimilarity(capsuleEmotions, targetEmotions)
            score += emotionalSimilarity * 0.4
        }
        
        // Topic similarity (simplified - would use embeddings in production)
        if let capsuleTopics = capsule.metadata?.topics,
           let targetTopics = target.metadata?.topics {
            let topicOverlap = calculateTopicOverlap(capsuleTopics, targetTopics)
            score += topicOverlap * 0.3
        }
        
        return min(1.0, score)
    }
    
    private func calculateEmotionalSimilarity(_ emotions1: [EmotionScore], _ emotions2: [EmotionScore]) -> Double {
        let emotions1Dict = Dictionary(uniqueKeysWithValues: emotions1.map { ($0.emotion, $0.score) })
        let emotions2Dict = Dictionary(uniqueKeysWithValues: emotions2.map { ($0.emotion, $0.score) })
        
        let allEmotions = Set(emotions1Dict.keys).union(Set(emotions2Dict.keys))
        
        var dotProduct = 0.0
        var norm1 = 0.0
        var norm2 = 0.0
        
        for emotion in allEmotions {
            let score1 = emotions1Dict[emotion] ?? 0.0
            let score2 = emotions2Dict[emotion] ?? 0.0
            
            dotProduct += score1 * score2
            norm1 += score1 * score1
            norm2 += score2 * score2
        }
        
        guard norm1 > 0 && norm2 > 0 else { return 0.0 }
        return dotProduct / (sqrt(norm1) * sqrt(norm2))
    }
    
    private func calculateTopicOverlap(_ topics1: [String], _ topics2: [String]) -> Double {
        let set1 = Set(topics1)
        let set2 = Set(topics2)
        let intersection = set1.intersection(set2)
        let union = set1.union(set2)
        
        guard !union.isEmpty else { return 0.0 }
        return Double(intersection.count) / Double(union.count)
    }
    
    private func buildTimeContext(for capsule: Capsule) -> TimeContext {
        let now = Date()
        let calendar = Calendar.current
        
        let timeSinceLastCapsule = now.timeIntervalSince(capsule.createdAt)
        
        let hour = calendar.component(.hour, from: now)
        let timeOfDay: String
        switch hour {
        case 6..<12:
            timeOfDay = "morning"
        case 12..<17:
            timeOfDay = "afternoon"
        case 17..<21:
            timeOfDay = "evening"
        default:
            timeOfDay = "night"
        }
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let dayOfWeek = dayFormatter.string(from: now)
        
        return TimeContext(
            currentTime: now,
            timeSinceLastCapsule: timeSinceLastCapsule,
            timeOfDay: timeOfDay,
            dayOfWeek: dayOfWeek
        )
    }
    
    private func buildEmotionalContext(from capsules: [Capsule]) -> EmotionalContext? {
        let recentCapsules = capsules
            .filter { $0.status == .completed }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10)
        
        let allEmotions = recentCapsules.compactMap { $0.metadata?.emotions }.flatMap { $0 }
        guard !allEmotions.isEmpty else { return nil }
        
        // Calculate average emotions
        let emotionGroups = Dictionary(grouping: allEmotions) { $0.emotion }
        let recentEmotions = emotionGroups.map { emotion, scores in
            let averageScore = scores.map { $0.score }.reduce(0, +) / Double(scores.count)
            let averageConfidence = scores.map { $0.confidence }.reduce(0, +) / Double(scores.count)
            return EmotionScore(emotion: emotion, score: averageScore, confidence: averageConfidence)
        }.sorted { $0.score > $1.score }
        
        return EmotionalContext(
            recentEmotions: Array(recentEmotions.prefix(5)),
            emotionalTrend: determineEmotionalTrend(from: recentCapsules),
            moodStability: calculateMoodStability(from: recentCapsules)
        )
    }
    
    private func determineEmotionalTrend(from capsules: [Capsule]) -> String? {
        // Simplified trend analysis
        guard capsules.count >= 3 else { return nil }
        
        let recentMood = capsules.prefix(3).compactMap { $0.metadata?.emotions?.first?.score }.reduce(0, +) / 3
        let olderMood = capsules.dropFirst(3).prefix(3).compactMap { $0.metadata?.emotions?.first?.score }.reduce(0, +) / 3
        
        if recentMood > olderMood + 0.1 {
            return "improving"
        } else if recentMood < olderMood - 0.1 {
            return "declining"
        } else {
            return "stable"
        }
    }
    
    private func calculateMoodStability(from capsules: [Capsule]) -> Double? {
        let emotions = capsules.compactMap { $0.metadata?.emotions?.first?.score }
        guard emotions.count >= 2 else { return nil }
        
        let mean = emotions.reduce(0, +) / Double(emotions.count)
        let variance = emotions.map { pow($0 - mean, 2) }.reduce(0, +) / Double(emotions.count)
        
        return 1.0 / (1.0 + sqrt(variance)) // Higher value = more stable
    }
    
    private func encodeContext(_ context: ConversationContext) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(context)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    
    // MARK: - Audio Streaming
    
    func streamAudioResponse(from url: URL) -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream { continuation in
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                
                if let data = data {
                    continuation.yield(data)
                }
                
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
            
            task.resume()
        }
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Audio Playback
    
    func playAudioMessage(_ message: ConversationMessage) async throws {
        guard let audioURL = message.audioURL else {
            throw AIAgentError.noAudioAvailable
        }
        
        // Stop any currently playing audio
        stopCurrentAudio()
        
        do {
            let audioData = try Data(contentsOf: audioURL)
            let player = try AVAudioPlayer(data: audioData)
            
            audioPlayers[message.id] = player
            
            return try await withCheckedThrowingContinuation { continuation in
                player.delegate = AudioPlayerDelegate { success in
                    self.audioPlayers.removeValue(forKey: message.id)
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AIAgentError.audioPlaybackFailed)
                    }
                }
                
                if player.play() {
                    // Audio started successfully
                } else {
                    continuation.resume(throwing: AIAgentError.audioPlaybackFailed)
                }
            }
        } catch {
            throw AIAgentError.audioPlaybackFailed
        }
    }
    
    func stopCurrentAudio() {
        audioPlayers.values.forEach { $0.stop() }
        audioPlayers.removeAll()
    }
    
    func isPlayingAudio(for messageId: String) -> Bool {
        return audioPlayers[messageId]?.isPlaying ?? false
    }
}

// MARK: - Audio Player Delegate

private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let completion: (Bool) -> Void
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completion(flag)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        completion(false)
    }
}

// MARK: - Errors

enum AIAgentError: LocalizedError {
    case noAudioAvailable
    case audioPlaybackFailed
    case conversationTimeLocked
    case contextBuildingFailed
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .noAudioAvailable:
            return "No audio available for this message"
        case .audioPlaybackFailed:
            return "Failed to play audio response"
        case .conversationTimeLocked:
            return "This conversation is currently time-locked"
        case .contextBuildingFailed:
            return "Failed to build conversation context"
        case .invalidResponse:
            return "Invalid response from AI service"
        }
    }
}