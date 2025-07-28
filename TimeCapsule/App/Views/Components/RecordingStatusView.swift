import SwiftUI

struct RecordingStatusView: View {
    let isRecording: Bool
    let duration: String
    let pulseScale: CGFloat
    
    var body: some View {
        Group {
            if isRecording {
                VStack(spacing: 6) {
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
                    
                    Text(duration)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .monospaced()
                        .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.durationLabel)
                        .accessibilityLabel("Recording duration: \(duration)")
                }
            } else {
                VStack(spacing: 6) {
                    Text("Ready to record")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text("Tap the microphone to capture your moment")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .dynamicTypeSize(.small...(.accessibility1))
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.CallScreen.statusLabel)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
    }
}