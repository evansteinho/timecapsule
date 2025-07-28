import SwiftUI

struct PastSelfChatView: View {
    @StateObject private var viewModel: ConversationViewModel
    @State private var scrollViewReader: ScrollViewReader?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    init(capsule: Capsule) {
        self._viewModel = StateObject(wrappedValue: ConversationViewModel(capsule: capsule))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if viewModel.isConversationTimeLocked {
                        timeLockBanner
                    }
                    
                    if viewModel.isLoading {
                        loadingView
                    } else {
                        chatContent
                    }
                    
                    if !viewModel.isConversationTimeLocked {
                        messageInputArea
                    }
                }
            }
            .navigationTitle(viewModel.conversationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.startConversation()
            }
            .alert("Conversation Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An unknown error occurred")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var timeLockBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "lock.circle.fill")
                    .foregroundColor(.orange)
                
                Text(viewModel.timeLockDescription ?? "Conversation is time-locked")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.1))
            
            Button("Check Status") {
                Task {
                    await viewModel.checkTimeLockStatus()
                }
            }
            .font(.caption)
            .foregroundColor(.blue)
            .padding(.bottom, 8)
            .accessibilityLabel("Check time lock status")
            .accessibilityHint("Check if the conversation is now available")
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.Chat.timeLockBanner)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conversation time locked. \(viewModel.timeLockDescription ?? "Conversation is time-locked")")
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Starting conversation with your past self...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Capsule preview header
                    capsulePreviewHeader
                    
                    // Chat messages
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            isPlaying: viewModel.currentlyPlayingMessage == message.id,
                            onPlayAudio: {
                                Task {
                                    await viewModel.toggleAudioPlayback(for: message)
                                }
                            }
                        )
                        .id(message.id)
                    }
                    
                    // Typing indicator
                    if viewModel.isTyping {
                        TypingIndicatorView()
                            .padding(.leading, 16)
                    }
                    
                    // Audio generation indicator
                    if viewModel.isGeneratingAudio {
                        AudioGenerationIndicatorView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .onAppear {
                scrollViewReader = proxy
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Chat.messageList)
            .accessibilityElement(children: .contain)
            .onChange(of: viewModel.messages.count) { _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.localState.scrollToMessageId) { messageId in
                if let messageId = messageId {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(messageId, anchor: .center)
                    }
                }
            }
        }
    }
    
    private var capsulePreviewHeader: some View {
        VStack(spacing: 12) {
            Text("Conversation Context")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(viewModel.capsulePreview)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            
            Text("You're now chatting with your past self about this moment")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    private var messageInputArea: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Ask your past self anything...", text: $viewModel.currentMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(viewModel.isTyping)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Chat.messageInput)
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type your message to ask your past self")
                
                Button(action: {
                    Task {
                        await viewModel.sendMessage()
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.canSendMessage ? .blue : .gray)
                }
                .disabled(!viewModel.canSendMessage)
                .accessibilityIdentifier(AccessibilityIdentifiers.Chat.sendButton)
                .accessibilityLabel("Send message")
                .accessibilityHint(viewModel.canSendMessage ? "Send your message to your past self" : "Complete typing your message to send")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
    }
}

struct MessageBubbleView: View {
    let message: ConversationMessage
    let isPlaying: Bool
    let onPlayAudio: () -> Void
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if message.role == .assistant {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                    
                    Text(message.role.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(message.role == .user ? .trailing : .leading)
                    
                    // Audio play button for assistant messages
                    if message.role == .assistant && message.audioURL != nil {
                        Button(action: onPlayAudio) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Chat.audioPlayButton)
                        .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio")
                        .accessibilityHint(isPlaying ? "Pause the audio message from your past self" : "Play the audio message from your past self")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(message.role == .user ? Color.blue : Color(UIColor.secondarySystemGroupedBackground))
            )
            .foregroundColor(message.role == .user ? .white : .primary)
            
            if message.role == .assistant {
                Spacer(minLength: 50)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(message.role == .user ? .staticText : .playsSound)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private var accessibilityLabel: String {
        var label = "\(message.role.displayName): \(message.content)"
        if message.role == .assistant && message.audioURL != nil {
            label += isPlaying ? ", audio playing" : ", audio available"
        }
        return label
    }
}

struct TypingIndicatorView: View {
    @State private var dotCount = 0
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
            
            Text("Past Self")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .opacity(dotCount > index ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.6), value: dotCount)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
            
            Spacer(minLength: 50)
        }
        .onAppear {
            startAnimation()
        }
        .accessibilityLabel("Past self is typing")
        .accessibilityIdentifier(AccessibilityIdentifiers.Chat.typingIndicator)
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { timer in
            dotCount = (dotCount + 1) % 4
            if dotCount == 0 {
                dotCount = 1
            }
        }
    }
}

struct AudioGenerationIndicatorView: View {
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
            
            Text("Past Self")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                    .scaleEffect(pulseScale)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseScale)
                
                Text("Generating voice...")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.1))
            )
            
            Spacer(minLength: 50)
        }
        .onAppear {
            pulseScale = 1.2
        }
        .accessibilityLabel("Generating voice response")
        .accessibilityIdentifier(AccessibilityIdentifiers.Chat.typingIndicator)
    }
}

#Preview {
    let sampleCapsule = Capsule(
        id: "sample-capsule",
        userId: "user-123",
        audioURL: URL(string: "https://example.com/audio.wav"),
        transcription: "Today was an interesting day. I learned something new about myself and wanted to capture this moment for future reflection.",
        duration: 45.0,
        fileSize: 2048,
        createdAt: Date().addingTimeInterval(-86400), // Yesterday
        updatedAt: Date(),
        status: .completed,
        metadata: CapsuleMetadata(
            emotions: [
                EmotionScore(emotion: "reflective", score: 0.8, confidence: 0.9),
                EmotionScore(emotion: "hopeful", score: 0.6, confidence: 0.7)
            ],
            topics: ["self-discovery", "learning", "growth"],
            summary: "A reflective moment about personal growth and learning"
        )
    )
    
    PastSelfChatView(capsule: sampleCapsule)
}