import SwiftUI

struct UploadProgressView: View {
    let progress: Double
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            // Progress card
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                
                VStack(spacing: 12) {
                    Text("Uploading Voice Capsule")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Saving your moment to the cloud...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(CustomProgressViewStyle())
                        .frame(height: 8)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Upload.progressBar)
                        .accessibilityValue("\(Int(progress * 100)) percent complete")
                    
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .accessibilityIdentifier(AccessibilityIdentifiers.Upload.progressLabel)
                        
                        Spacer()
                        
                        Text("Please wait...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.Upload.progressView)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Uploading voice capsule, \(Int(progress * 100)) percent complete")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct CustomProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                
                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
                    .animation(.easeInOut(duration: 0.3), value: configuration.fractionCompleted)
            }
        }
    }
}

#Preview {
    UploadProgressView(progress: 0.65)
}