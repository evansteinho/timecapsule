import Foundation
import AuthenticationServices
import Combine

/// Protocol defining authentication capabilities for TimeCapsule
///
/// Manages Sign in with Apple integration, JWT token lifecycle,
/// and secure credential storage using iOS Keychain.
protocol AuthServiceProtocol {
    var isAuthenticated: Bool { get }
    var currentUser: User? { get }
    var authStatePublisher: AnyPublisher<AuthState, Never> { get }
    
    func signInWithApple() async throws -> AuthResponse
    func refreshToken() async throws -> AuthToken
    func signOut()
    func getValidToken() async throws -> String
}

enum AuthState {
    case unauthenticated
    case authenticated(User)
    case loading
}

/// Primary authentication service for TimeCapsule app
///
/// Handles the complete authentication flow:
/// 1. Sign in with Apple credential validation
/// 2. Backend JWT token exchange and management
/// 3. Automatic token refresh with 5-minute buffer
/// 4. Secure token storage in iOS Keychain
/// 5. Reactive authentication state management
@MainActor
final class AuthService: NSObject, ObservableObject, AuthServiceProtocol {
    @Published private(set) var authState: AuthState = .unauthenticated
    @Published private(set) var currentUser: User?
    
    private var authToken: AuthToken?
    private let keychain = KeychainHelper()
    private let networkService: NetworkServiceProtocol
    
    var isAuthenticated: Bool {
        switch authState {
        case .authenticated:
            return true
        default:
            return false
        }
    }
    
    var authStatePublisher: AnyPublisher<AuthState, Never> {
        $authState.eraseToAnyPublisher()
    }
    
    init(networkService: NetworkServiceProtocol = NetworkService()) {
        self.networkService = networkService
        super.init()
        loadStoredAuth()
    }
    
    private func loadStoredAuth() {
        Task {
            if let tokenData = keychain.load(key: "auth_token"),
               let token = try? JSONDecoder().decode(AuthToken.self, from: tokenData),
               !token.isExpired {
                
                self.authToken = token
                
                // Try to refresh token and get user info
                do {
                    let refreshedToken = try await refreshToken()
                    self.authToken = refreshedToken
                    networkService.setAuthToken(refreshedToken.accessToken)
                    
                    let user = try await fetchCurrentUser()
                    self.currentUser = user
                    self.authState = .authenticated(user)
                } catch {
                    // If refresh fails, sign out
                    self.signOut()
                }
            }
        }
    }
    
    func signInWithApple() async throws -> AuthResponse {
        authState = .loading
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = SignInWithAppleDelegate { result in
                Task {
                    switch result {
                    case .success(let credential):
                        do {
                            let authResponse = try await self.authenticateWithBackend(credential: credential)
                            await MainActor.run {
                                self.handleSuccessfulAuth(authResponse)
                            }
                            continuation.resume(returning: authResponse)
                        } catch {
                            await MainActor.run {
                                self.authState = .unauthenticated
                            }
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        await MainActor.run {
                            self.authState = .unauthenticated
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
            controller.presentationContextProvider = SignInWithApplePresentationContext()
            controller.performRequests()
        }
    }
    
    private func authenticateWithBackend(credential: ASAuthorizationAppleIDCredential) async throws -> AuthResponse {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredentials
        }
        
        let requestBody: [String: Any] = [
            "identity_token": tokenString,
            "user_identifier": credential.user,
            "email": credential.email ?? "",
            "full_name": [
                "given_name": credential.fullName?.givenName ?? "",
                "family_name": credential.fullName?.familyName ?? ""
            ]
        ]
        
        let response: AuthResponse = try await networkService.post(
            path: "/auth/apple",
            body: requestBody
        )
        
        return response
    }
    
    func refreshToken() async throws -> AuthToken {
        guard let currentToken = authToken else {
            throw AuthError.noToken
        }
        
        let requestBody: [String: Any] = [
            "refresh_token": currentToken.refreshToken
        ]
        
        let newToken: AuthToken = try await networkService.post(
            path: "/auth/refresh",
            body: requestBody
        )
        
        // Store new token
        if let tokenData = try? JSONEncoder().encode(newToken) {
            keychain.save(data: tokenData, key: "auth_token")
        }
        
        // Update network service with new token
        networkService.setAuthToken(newToken.accessToken)
        
        return newToken
    }
    
    func getValidToken() async throws -> String {
        guard let token = authToken else {
            throw AuthError.noToken
        }
        
        if token.isExpired {
            let refreshedToken = try await refreshToken()
            self.authToken = refreshedToken
            networkService.setAuthToken(refreshedToken.accessToken)
            return refreshedToken.accessToken
        }
        
        return token.accessToken
    }
    
    private func fetchCurrentUser() async throws -> User {
        let user: User = try await networkService.get(path: "/user/me")
        return user
    }
    
    func signOut() {
        authToken = nil
        currentUser = nil
        authState = .unauthenticated
        keychain.delete(key: "auth_token")
        networkService.setAuthToken(nil)
    }
    
    private func handleSuccessfulAuth(_ authResponse: AuthResponse) {
        self.authToken = authResponse.token
        self.currentUser = authResponse.user
        self.authState = .authenticated(authResponse.user)
        
        // Store token in keychain
        if let tokenData = try? JSONEncoder().encode(authResponse.token) {
            keychain.save(data: tokenData, key: "auth_token")
        }
        
        // Update network service with new token
        networkService.setAuthToken(authResponse.token.accessToken)
    }
}

// MARK: - Sign in with Apple Delegate
private class SignInWithAppleDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let completion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void
    
    init(completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        self.completion = completion
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            completion(.success(credential))
        } else {
            completion(.failure(AuthError.invalidCredentials))
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}

// MARK: - Presentation Context Provider
private class SignInWithApplePresentationContext: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available for Sign in with Apple")
        }
        return window
    }
}

// MARK: - Auth Errors
enum AuthError: LocalizedError {
    case invalidCredentials
    case noToken
    case networkError
    case tokenExpired
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials provided"
        case .noToken:
            return "No authentication token available"
        case .networkError:
            return "Network error occurred"
        case .tokenExpired:
            return "Authentication token has expired"
        }
    }
}