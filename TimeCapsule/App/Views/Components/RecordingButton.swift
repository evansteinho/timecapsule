import SwiftUI

struct RecordingButton: View {
    let isRecording: Bool
    let hasPermissions: Bool
    let action: () -> Void
    
    @State private var buttonScale: CGFloat = 1.0
    @State private var pulseScale: CGFloat = 1.0
    @ScaledMetric(relativeTo: .largeTitle) private var buttonSize: CGFloat = 120
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 36
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                buttonScale = 0.95
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    buttonScale = 1.0
                }
            }
            
            HapticFeedback.impact(.medium)
            action()
        }) {
            ZStack {
                // Outer glow ring when recording
                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: buttonSize + 20, height: buttonSize + 20)
                        .scaleEffect(pulseScale)
                }
                
                // Main button
                Circle()
                    .fill(
                        isRecording 
                        ? Color.accessibleRecordingActive
                        : LinearGradient(
                            colors: [Color.accessibleRecordingReady, Color.accessibleRecordingReady.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: buttonSize, height: buttonSize)
                    .shadow(
                        color: isRecording ? Color.accessibleRecordingActive.opacity(0.3) : Color.accessibleRecordingReady.opacity(0.3),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                
                // Icon
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: iconSize * 0.6, height: iconSize * 0.6)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: iconSize, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(buttonScale)
        .disabled(!hasPermissions)
        .opacity(hasPermissions ? 1.0 : 0.5)
        .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.recordButton)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(isRecording ? "Tap to stop recording your voice capsule" : "Tap to start recording your voice capsule")
        .accessibilityAddTraits(hasPermissions ? .none : .notEnabled)
        .onAppear {
            if isRecording {
                pulseScale = 1.1
            }
        }
        .onChange(of: isRecording) { _, recording in
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = recording ? 1.1 : 1.0
            }
        }
    }
}