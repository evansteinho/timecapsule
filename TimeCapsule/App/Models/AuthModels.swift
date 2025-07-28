import Foundation

// MARK: - Authentication Response Models

struct AuthResponse: Codable {
    let token: AuthToken
    let user: User
    
    enum CodingKeys: String, CodingKey {
        case token
        case user
    }
}

struct AuthToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case tokenType = "token_type"
    }
    
    var isExpired: Bool {
        // Add 5-minute buffer for token refresh
        let bufferTime: TimeInterval = 300 // 5 minutes
        return Date().addingTimeInterval(bufferTime) > expiresAt
    }
    
    var isValid: Bool {
        return !accessToken.isEmpty && !refreshToken.isEmpty && !isExpired
    }
}

// MARK: - Sign in with Apple Request/Response

struct AppleSignInRequest: Codable {
    let identityToken: String
    let userIdentifier: String
    let email: String?
    let fullName: AppleUserName?
    
    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case userIdentifier = "user_identifier"
        case email
        case fullName = "full_name"
    }
}

struct AppleUserName: Codable {
    let givenName: String?
    let familyName: String?
    
    enum CodingKeys: String, CodingKey {
        case givenName = "given_name"
        case familyName = "family_name"
    }
}

// MARK: - Token Refresh Models

struct TokenRefreshRequest: Codable {
    let refreshToken: String
    
    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct TokenRefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}