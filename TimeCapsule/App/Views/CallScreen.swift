import SwiftUI

struct CallScreen: View {
    @StateObject private var viewModel: CallViewModel
    @State private var pulseScale: CGFloat = 1.0
    @State private var recordButtonScale: CGFloat = 1.0
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authService: AuthService
    
    init() {
        // Create a temporary auth service that will be replaced by environment object
        self._viewModel = StateObject(wrappedValue: CallViewModel(authService: AuthService()))
    }
    
    init(authService: AuthServiceProtocol) {
        self._viewModel = StateObject(wrappedValue: CallViewModel(authService: authService))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header section
                    headerSection
                        .frame(height: geometry.size.height * 0.25)
                    
                    // Waveform section
                    waveformSection
                        .frame(height: geometry.size.height * 0.3)
                    
                    // Recording controls section
                    recordingControlsSection
                        .frame(height: geometry.size.height * 0.35)
                    
                    // Permission prompt (if needed)
                    if !viewModel.hasPermissions {
                        PermissionPromptView()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                    }
                    
                    Spacer(minLength: 20)
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Recording Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $viewModel.showSignIn) {
            SignInView(viewModel: viewModel)
        }
        .overlay(
            Group {
                if viewModel.isUploading {
                    UploadProgressView(progress: viewModel.uploadProgress)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        )
        .alert("Upload Complete", isPresented: .constant(viewModel.uploadCompleted)) {
            Button("OK") {
                viewModel.dismissUploadResult()
            }
        } message: {
            Text("Your voice capsule has been saved successfully!")
        }
        .alert("Upload Failed", isPresented: .constant(viewModel.uploadFailed)) {
            Button("Retry") {
                viewModel.retryUpload()
            }
            Button("Cancel", role: .cancel) {
                viewModel.dismissUploadResult()
            }
        } message: {
            Text(viewModel.uploadErrorMessage ?? "Failed to upload your voice capsule.")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // App icon or visual element
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("Voice Capsule")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                statusText
                    .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.statusLabel)
                    .accessibleTransition(.opacity, fallback: .identity)
                    .accessibleAnimation(.easeInOut(duration: 0.3), value: viewModel.isRecording, fallback: nil)
            }
            
            Spacer()
        }
    }
    
    private var statusText: some View {
        Group {
            if viewModel.isRecording {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(pulseScale > 1.0 ? 1.0 : 0.5)
                        
                        Text("Recording")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                    
                    Text(viewModel.formattedDuration)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .monospaced()
                        .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.durationLabel)
                        .accessibilityLabel("Recording duration: \(viewModel.formattedDuration)")
                }
            } else {
                VStack(spacing: 4) {
                    Text("Ready to record")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text("Tap the microphone to capture your moment")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    private var waveformSection: some View {
        VStack(spacing: 20) {
            if viewModel.isRecording || viewModel.meterLevel > 0 {
                WaveformView(
                    meterLevel: viewModel.meterLevel,
                    isRecording: viewModel.isRecording
                )
                .frame(height: 120)
                .padding(.horizontal, 32)
                .accessibleTransition(.scale.combined(with: .opacity), fallback: .opacity)
                .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.waveform)
                .accessibilityLabel("Audio waveform visualization")
                .accessibilityValue(viewModel.isRecording ? "Recording active, audio level \(Int(viewModel.meterLevel * 100)) percent" : "Ready to record")
                .accessibilityHidden(!viewModel.isRecording) // Hide when not recording to reduce clutter
            } else {
                // Placeholder waveform when not recording
                WaveformPlaceholderView()
                    .frame(height: 120)
                    .padding(.horizontal, 32)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.isRecording)
    }
    
    private var recordingControlsSection: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Main record button
            recordButton
            
            // Secondary actions
            secondaryActions
            
            Spacer()
        }
    }
    
    private var recordButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                recordButtonScale = 0.95
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    recordButtonScale = 1.0
                }
            }
            
            HapticFeedback.impact(.medium)
            viewModel.toggleRecording()
        }) {
            ZStack {
                // Outer glow ring when recording
                if viewModel.isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseScale)
                }
                
                // Main button
                Circle()
                    .fill(
                        viewModel.isRecording 
                        ? Color.red
                        : LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(
                        color: viewModel.isRecording ? Color.red.opacity(0.3) : Color.blue.opacity(0.3),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                
                // Icon
                Group {
                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(recordButtonScale)
        .disabled(!viewModel.hasPermissions)
        .opacity(viewModel.hasPermissions ? 1.0 : 0.5)
        .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.recordButton)
        .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(viewModel.isRecording ? "Tap to stop recording your voice capsule" : "Tap to start recording your voice capsule")
        .accessibilityAddTraits(viewModel.hasPermissions ? .none : .notEnabled)
        .onAppear {
            if viewModel.isRecording {
                pulseScale = 1.1
            }
        }
        .onChange(of: viewModel.isRecording) { _, isRecording in
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = isRecording ? 1.1 : 1.0
            }
        }
    }
    
    private var secondaryActions: some View {
        VStack(spacing: 16) {
            if viewModel.isRecording {
                Button("Cancel Recording") {
                    HapticFeedback.impact(.light)
                    viewModel.cancelRecording()
                }
                .font(.headline)
                .foregroundColor(.red)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.cancelButton)
                .accessibilityLabel("Cancel recording")
                .accessibilityHint("Tap to cancel the current recording")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            if !viewModel.hasPermissions {
                Text("Microphone permission required")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.isRecording)
    }
}

struct WaveformView: View {
    let meterLevel: Double
    let isRecording: Bool
    
    private let barCount = 50
    @State private var animationValues: [CGFloat] = Array(repeating: 0, count: 50)
    
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: barColors(for: index),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3)
                    .frame(height: barHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.1)
                        .delay(Double(index) * 0.01),
                        value: meterLevel
                    )
            }
        }
        .onAppear {
            animationValues = Array(repeating: 0, count: barCount)
        }
    }
    
    private func barColors(for index: Int) -> [Color] {
        let normalizedIndex = Double(index) / Double(barCount - 1)
        let centerDistance = abs(normalizedIndex - 0.5)
        
        if isRecording {
            if centerDistance < 0.2 {
                return [Color.blue, Color.purple]
            } else if centerDistance < 0.4 {
                return [Color.blue.opacity(0.8), Color.blue]
            } else {
                return [Color.blue.opacity(0.4), Color.blue.opacity(0.6)]
            }
        } else {
            return [Color.gray.opacity(0.2), Color.gray.opacity(0.3)]
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 2
        let maxHeight: CGFloat = 100
        
        guard isRecording else { return baseHeight }
        
        let normalizedIndex = Double(index) / Double(barCount - 1)
        let centerDistance = abs(normalizedIndex - 0.5) * 2
        
        // Create a more realistic waveform pattern
        let frequencyFactor = sin(normalizedIndex * .pi * 3) * 0.5 + 0.5
        let levelMultiplier = meterLevel * (1.0 - centerDistance * 0.3) * frequencyFactor
        let randomVariation = Double.random(in: 0.7...1.3)
        
        let height = baseHeight + CGFloat(levelMultiplier * randomVariation) * (maxHeight - baseHeight)
        return max(baseHeight, height)
    }
}

struct WaveformPlaceholderView: View {
    @State private var animateGradient = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<50, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.gray.opacity(0.1),
                                Color.gray.opacity(0.2),
                                Color.gray.opacity(0.1)
                            ],
                            startPoint: animateGradient ? .leading : .trailing,
                            endPoint: animateGradient ? .trailing : .leading
                        )
                    )
                    .frame(width: 3)
                    .frame(height: placeholderHeight(for: index))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private func placeholderHeight(for index: Int) -> CGFloat {
        let normalizedIndex = Double(index) / 49.0
        let wave = sin(normalizedIndex * .pi * 2) * 15 + 20
        return CGFloat(wave)
    }
}

struct PermissionPromptView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Icon with background
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 12) {
                Text("Microphone Access Required")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("TimeCapsule needs microphone access to record your voice capsules. This allows you to capture and preserve your precious moments.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
            }
            
            Button(action: {
                HapticFeedback.impact(.light)
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("Open Settings")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.openSettingsButton)
            .accessibilityLabel("Open Settings to enable microphone access")
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.permissionPrompt)
        .accessibilityElement(children: .combine)
    }
}


#Preview {
    CallScreen()
}