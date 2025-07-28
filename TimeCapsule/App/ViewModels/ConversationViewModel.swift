import Foundation
import Combine

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published var conversation: Conversation?
    @Published var messages: [ConversationMessage] = []
    @Published var isLoading = false
    @Published var isTyping = false
    @Published var currentMessage = ""
    @Published var error: Error?
    @Published var showError = false
    @Published var timeLockInfo: TimeLockInfo?
    @Published var localState = LocalConversationState()
    
    // Audio playback state
    @Published var currentlyPlayingMessage: String?
    @Published var isGeneratingAudio = false
    
    private let aiAgentService: AIAgentServiceProtocol
    private let capsule: Capsule
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    
    init(capsule: Capsule, aiAgentService: AIAgentServiceProtocol = AIAgentService()) {
        self.capsule = capsule
        self.aiAgentService = aiAgentService
    }
    
    // MARK: - Conversation Lifecycle
    
    func startConversation(with initialMessage: String? = nil) async {
        isLoading = true
        error = nil
        
        do {
            let response = try await aiAgentService.startConversation(
                with: capsule,
                initialMessage: initialMessage
            )
            
            conversation = response.conversation
            messages = response.conversation.messages
            timeLockInfo = response.timeLockInfo
            
            // If there's an initial response, add it and play audio if available
            if let initialResponse = response.initialResponse {
                messages.append(initialResponse)
                
                if let audioURL = initialResponse.audioURL {
                    await playAudioForMessage(initialResponse)
                }
            }
            
        } catch {
            handleError(error)
        }
        
        isLoading = false
    }
    
    func sendMessage() async {
        guard !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let conversationId = conversation?.id else { return }
        
        let messageContent = currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        currentMessage = ""
        
        // Add user message immediately for better UX
        let userMessage = ConversationMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            content: messageContent,
            role: .user,
            audioURL: nil,
            timestamp: Date(),
            metadata: nil
        )
        
        messages.append(userMessage)
        
        // Start typing indicator
        isTyping = true
        localState.isTyping = true
        
        do {
            let response = try await aiAgentService.sendMessage(
                messageContent,
                to: conversationId,
                requestAudio: true
            )
            
            // Check for time lock
            if response.isTimeLocked {
                timeLockInfo = try await aiAgentService.checkTimeLock(for: conversationId)
                handleTimeLock()
                return
            }
            
            // Add AI response
            messages.append(response.message)
            
            // Handle audio response
            if let audioURL = response.audioStreamURL {
                isGeneratingAudio = true
                await streamAndPlayAudio(from: audioURL, for: response.message)
            } else if let audioURL = response.message.audioURL {
                await playAudioForMessage(response.message)
            }
            
        } catch {
            handleError(error)
        }
        
        isTyping = false
        localState.isTyping = false
        isGeneratingAudio = false
    }
    
    // MARK: - Audio Handling
    
    func playAudioForMessage(_ message: ConversationMessage) async {
        guard message.role == .assistant else { return }
        
        currentlyPlayingMessage = message.id
        localState.isPlayingAudio = true
        localState.currentlyPlayingMessageId = message.id
        
        do {
            try await aiAgentService.playAudioMessage(message)
        } catch {
            handleError(error)
        }
        
        currentlyPlayingMessage = nil
        localState.isPlayingAudio = false
        localState.currentlyPlayingMessageId = nil
    }
    
    func stopAudio() {
        aiAgentService.stopCurrentAudio()
        currentlyPlayingMessage = nil
        localState.isPlayingAudio = false
        localState.currentlyPlayingMessageId = nil
    }
    
    func toggleAudioPlayback(for message: ConversationMessage) async {
        if currentlyPlayingMessage == message.id {
            stopAudio()
        } else {
            await playAudioForMessage(message)
        }
    }
    
    private func streamAndPlayAudio(from url: URL, for message: ConversationMessage) async {
        do {
            // Stream audio data and play progressively
            var audioData = Data()
            
            for try await chunk in aiAgentService.streamAudioResponse(from: url) {
                audioData.append(chunk)
                
                // TODO: Implement progressive audio playback
                // For now, wait for complete download
            }
            
            // Play the complete audio
            currentlyPlayingMessage = message.id
            localState.isPlayingAudio = true
            localState.currentlyPlayingMessageId = message.id
            
            try await aiAgentService.playAudioMessage(message)
            
            currentlyPlayingMessage = nil
            localState.isPlayingAudio = false
            localState.currentlyPlayingMessageId = nil
            
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - Time Lock Handling
    
    private func handleTimeLock() {
        // Show time lock UI state
        localState.errorMessage = "This conversation is currently time-locked. Please try again later."
    }
    
    func checkTimeLockStatus() async {
        guard let conversationId = conversation?.id else { return }
        
        do {
            timeLockInfo = try await aiAgentService.checkTimeLock(for: conversationId)
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        self.error = error
        self.showError = true
        localState.errorMessage = error.localizedDescription
        
        // Stop any ongoing audio
        stopAudio()
        isGeneratingAudio = false
        isTyping = false
        localState.isTyping = false
    }
    
    func clearError() {
        error = nil
        showError = false
        localState.errorMessage = nil
    }
    
    // MARK: - UI State Management
    
    var canSendMessage: Bool {
        !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isTyping &&
        !isLoading &&
        !(timeLockInfo?.isCurrentlyLocked ?? false)
    }
    
    var isConversationTimeLocked: Bool {
        timeLockInfo?.isCurrentlyLocked ?? false
    }
    
    var timeLockDescription: String? {
        guard let timeLockInfo = timeLockInfo, timeLockInfo.isCurrentlyLocked else { return nil }
        
        if let timeUntilUnlock = timeLockInfo.timeUntilUnlock {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .abbreviated
            
            if let timeString = formatter.string(from: timeUntilUnlock) {
                return "Conversation unlocks in \(timeString)"
            }
        }
        
        return timeLockInfo.lockReason ?? "This conversation is currently locked"
    }
    
    var messageCount: Int {
        messages.count
    }
    
    var lastMessageFromPastSelf: ConversationMessage? {
        messages.last { $0.role == .assistant }
    }
    
    // MARK: - Message Management
    
    func scrollToMessage(id: String) {
        localState.scrollToMessageId = id
        
        // Clear after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.localState.scrollToMessageId = nil
        }
    }
    
    func scrollToBottom() {
        if let lastMessage = messages.last {
            scrollToMessage(id: lastMessage.id)
        }
    }
    
    // MARK: - Typing Indicator
    
    func startTypingIndicator() {
        typingTimer?.invalidate()
        isTyping = true
        localState.isTyping = true
        
        typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isTyping = false
                self?.localState.isTyping = false
            }
        }
    }
    
    func stopTypingIndicator() {
        typingTimer?.invalidate()
        isTyping = false
        localState.isTyping = false
    }
    
    // MARK: - Conversation Context
    
    var conversationTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Chat about \(formatter.string(from: capsule.createdAt))"
    }
    
    var capsulePreview: String {
        if let transcription = capsule.transcription {
            return String(transcription.prefix(100)) + (transcription.count > 100 ? "..." : "")
        } else {
            return "Voice capsule from \(DateFormatter.shortDate.string(from: capsule.createdAt))"
        }
    }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}