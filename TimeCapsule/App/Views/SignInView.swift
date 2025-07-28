import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @ObservedObject var viewModel: CallViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                // App icon and title
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 12) {
                        Text("Welcome to TimeCapsule")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Sign in to save and sync your voice capsules across all your devices")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Benefits
                VStack(spacing: 16) {
                    BenefitRow(
                        icon: "cloud.fill",
                        title: "Cloud Sync",
                        description: "Access your capsules anywhere"
                    )
                    
                    BenefitRow(
                        icon: "lock.shield.fill",
                        title: "Secure & Private",
                        description: "Your data is encrypted and protected"
                    )
                    
                    BenefitRow(
                        icon: "person.2.fill",
                        title: "AI Conversations",
                        description: "Chat with your past self using AI"
                    )
                }
                .padding(.horizontal)
                .accessibilityIdentifier(AccessibilityIdentifiers.SignIn.benefitsList)
                .accessibilityElement(children: .contain)
                
                Spacer()
                
                // Sign in button
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        // Handle the result
                        switch result {
                        case .success:
                            viewModel.signInWithApple()
                        case .failure(let error):
                            print("Sign in failed: \(error)")
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .accessibilityIdentifier(AccessibilityIdentifiers.SignIn.appleSignInButton)
                    .accessibilityLabel("Sign in with Apple")
                    .accessibilityHint("Sign in to sync your voice capsules across devices")
                    
                    Button("Continue without signing in") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .accessibilityLabel("Continue without signing in")
                    .accessibilityHint("Use the app without account sync")
                }
                .padding(.horizontal, 32)
                
                Spacer(minLength: 20)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

#Preview {
    SignInView(viewModel: CallViewModel(authService: AuthService()))
}