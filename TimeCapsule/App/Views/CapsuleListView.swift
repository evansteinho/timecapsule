import SwiftUI

struct CapsuleListView: View {
    @StateObject private var viewModel = CapsuleListViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var capsuleToDelete: Capsule?
    @State private var selectedCapsule: Capsule?
    @State private var showingConversation = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.capsules.isEmpty {
                    loadingView
                } else if viewModel.capsules.isEmpty {
                    emptyStateView
                } else {
                    capsuleListContent
                }
            }
            .navigationTitle("My Capsules")
            .navigationBarTitleDisplayMode(.large)
            .accessibilityIdentifier(AccessibilityIdentifiers.CapsuleList.list)
            .refreshable {
                await viewModel.refreshCapsules()
            }
            .task {
                await viewModel.loadCapsules()
            }
            .alert("Delete Capsule", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let capsule = capsuleToDelete {
                        viewModel.deleteCapsule(capsule)
                    }
                }
            } message: {
                Text("This action cannot be undone. The capsule and its transcription will be permanently deleted.")
            }
            .sheet(isPresented: $showingConversation) {
                if let capsule = selectedCapsule {
                    PastSelfChatView(capsule: capsule)
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .accessibilityLabel("Loading")
            Text("Loading your capsules...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityIdentifiers.CapsuleList.loadingState)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading your capsules")
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("No Capsules Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start recording your first voice capsule to begin your journey of self-reflection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button("Record Your First Capsule") {
                // User can switch to Record tab manually
                // This provides a helpful call-to-action
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Record Your First Capsule")
            .accessibilityHint("Switch to the record tab to start recording your first voice capsule")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityIdentifiers.CapsuleList.emptyState)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No capsules yet. Start recording your first voice capsule to begin your journey of self-reflection.")
    }
    
    private var capsuleListContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.groupedCapsules) { group in
                    CapsuleGroupView(
                        group: group,
                        onDelete: { capsule in
                            capsuleToDelete = capsule
                            showingDeleteConfirmation = true
                        },
                        onRetry: { capsule in
                            Task {
                                await viewModel.retryFailedCapsule(capsule)
                            }
                        },
                        onStartConversation: { capsule in
                            selectedCapsule = capsule
                            showingConversation = true
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

struct CapsuleGroupView: View {
    let group: CapsuleGroup
    let onDelete: (Capsule) -> Void
    let onRetry: (Capsule) -> Void
    let onStartConversation: (Capsule) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.displayDate)
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            ForEach(group.capsules) { capsule in
                CapsuleRowView(
                    capsule: capsule,
                    onDelete: { onDelete(capsule) },
                    onRetry: { onRetry(capsule) },
                    onStartConversation: { onStartConversation(capsule) }
                )
            }
        }
    }
}

struct CapsuleRowView: View {
    let capsule: Capsule
    let onDelete: () -> Void
    let onRetry: () -> Void
    let onStartConversation: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Status indicator
                statusIcon
                
                // Capsule content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(formattedTime)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Duration \(formattedDuration)")
                    }
                    
                    if let transcription = capsule.transcription, !transcription.isEmpty {
                        Text(transcription)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .accessibilityIdentifier(AccessibilityIdentifiers.CapsuleRow.transcription)
                    } else if capsule.status.isProcessing {
                        Text(capsule.status.displayName)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        Text("No transcription available")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    if let metadata = capsule.metadata {
                        metadataView(metadata)
                    }
                }
                
                // Action buttons
                actionButtons
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .contextMenu {
            if capsule.status == .failed {
                Button("Retry", systemImage: "arrow.clockwise") {
                    onRetry()
                }
            }
            
            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.CapsuleRow.container)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view details, use context menu for more actions")
    }
    
    private var statusIcon: some View {
        Group {
            switch capsule.status {
            case .uploading:
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityLabel("Uploading")
            case .processing, .transcribing:
                Image(systemName: "gear")
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 2) * 180))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: Date())
                    .accessibilityLabel(capsule.status == .processing ? "Processing" : "Transcribing")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .accessibilityLabel("Completed")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .accessibilityLabel("Failed")
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityIdentifier(AccessibilityIdentifiers.CapsuleRow.statusIcon)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 8) {
            if capsule.status == .completed {
                Button(action: onStartConversation) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier(AccessibilityIdentifiers.CapsuleRow.conversationButton)
                .accessibilityLabel("Start conversation")
                .accessibilityHint("Begin a conversation with your past self about this capsule")
            }
            
            if capsule.status == .failed {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.orange)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier(AccessibilityIdentifiers.CapsuleRow.retryButton)
                .accessibilityLabel("Retry upload")
                .accessibilityHint("Retry uploading this failed capsule")
            }
        }
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: capsule.createdAt)
    }
    
    private var formattedDuration: String {
        let minutes = Int(capsule.duration) / 60
        let seconds = Int(capsule.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func metadataView(_ metadata: CapsuleMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let emotions = metadata.emotions, !emotions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(emotions.prefix(3), id: \.emotion) { emotion in
                            Text(emotion.emotion)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            
            if let topics = metadata.topics, !topics.isEmpty {
                Text("Topics: \(topics.prefix(2).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Accessibility
extension CapsuleRowView {
    private var accessibilityLabel: String {
        var label = "Capsule recorded at \(formattedTime), duration \(formattedDuration)"
        
        switch capsule.status {
        case .uploading:
            label += ", uploading"
        case .processing:
            label += ", processing"
        case .transcribing:
            label += ", transcribing"
        case .completed:
            label += ", completed"
            if let transcription = capsule.transcription {
                label += ", transcription: \(transcription)"
            }
        case .failed:
            label += ", failed"
        }
        
        return label
    }
}

#Preview {
    CapsuleListView()
}