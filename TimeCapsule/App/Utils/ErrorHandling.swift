import Foundation
import SwiftUI

// MARK: - Comprehensive Error Handling System

/// Central error handling and recovery system for Time-Capsule app
final class ErrorHandlingService: ObservableObject {
    static let shared = ErrorHandlingService()
    
    @Published var currentError: AppError?
    @Published var showErrorAlert = false
    @Published var errorRecoveryInProgress = false
    
    private var errorHistory: [ErrorEvent] = []
    private let maxErrorHistory = 50
    
    private init() {}
    
    // MARK: - Error Reporting
    
    func reportError(_ error: Error, context: ErrorContext = .general) {
        let appError = AppError.from(error, context: context)
        recordError(appError, context: context)
        
        DispatchQueue.main.async {
            self.currentError = appError
            self.showErrorAlert = true
        }
        
        // Log error for debugging
        logError(appError, context: context)
        
        // Attempt automatic recovery if possible
        if appError.isRecoverable {
            attemptRecovery(for: appError, context: context)
        }
    }
    
    func reportError(_ appError: AppError, context: ErrorContext = .general) {
        recordError(appError, context: context)
        
        DispatchQueue.main.async {
            self.currentError = appError
            self.showErrorAlert = true
        }
        
        logError(appError, context: context)
        
        if appError.isRecoverable {
            attemptRecovery(for: appError, context: context)
        }
    }
    
    // MARK: - Error Recovery
    
    func attemptRecovery(for error: AppError, context: ErrorContext) {
        guard !errorRecoveryInProgress else { return }
        
        errorRecoveryInProgress = true
        
        Task {
            do {
                try await performRecovery(for: error, context: context)
                
                await MainActor.run {
                    self.errorRecoveryInProgress = false
                    self.currentError = nil
                    self.showErrorAlert = false
                }
            } catch {
                await MainActor.run {
                    self.errorRecoveryInProgress = false
                    // Show recovery failed error
                    let recoveryError = AppError.recoveryFailed(originalError: error, recoveryError: error)
                    self.currentError = recoveryError
                }
            }
        }
    }
    
    private func performRecovery(for error: AppError, context: ErrorContext) async throws {
        switch error {
        case .networkError(.networkUnavailable):
            try await recoverFromNetworkUnavailable()
        case .authenticationError(.tokenExpired):
            try await recoverFromExpiredToken()
        case .audioError(.permissionDenied):
            try await recoverFromAudioPermission()
        case .storageError(.insufficientSpace):
            try await recoverFromInsufficientStorage()
        case .persistenceError(.saveFailed):
            try await recoverFromSaveFailure()
        default:
            throw AppError.recoveryNotAvailable
        }
    }
    
    // MARK: - Specific Recovery Methods
    
    private func recoverFromNetworkUnavailable() async throws {
        // Wait for network to become available
        let reachability = NetworkReachability()
        reachability.startMonitoring()
        
        // Wait up to 30 seconds for connection
        for _ in 0..<30 {
            if reachability.isConnected {
                reachability.stopMonitoring()
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        reachability.stopMonitoring()
        throw AppError.recoveryFailed(originalError: .networkError(.networkUnavailable), recoveryError: AppError.recoveryTimeout)
    }
    
    private func recoverFromExpiredToken() async throws {
        // Attempt to refresh authentication
        let authService = AuthService()
        _ = try await authService.refreshToken()
    }
    
    private func recoverFromAudioPermission() async throws {
        // Guide user to settings
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            throw AppError.recoveryNotAvailable
        }
        
        await MainActor.run {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    private func recoverFromInsufficientStorage() async throws {
        // Clean up temporary files and old recordings
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in tempFiles {
                try? fileManager.removeItem(at: file)
            }
        } catch {
            // Continue with other cleanup
        }
        
        // Clean up old cached data
        URLCache.shared.removeAllCachedResponses()
        
        // Optimize Core Data memory usage
        EnhancedPersistenceService.shared.optimizeMemoryUsage()
    }
    
    private func recoverFromSaveFailure() async throws {
        // Reset Core Data context and try again
        let persistence = EnhancedPersistenceService.shared
        persistence.viewContext.rollback()
        persistence.viewContext.reset()
    }
    
    // MARK: - Error Tracking
    
    private func recordError(_ error: AppError, context: ErrorContext) {
        let event = ErrorEvent(error: error, context: context, timestamp: Date())
        errorHistory.append(event)
        
        // Maintain history limit
        if errorHistory.count > maxErrorHistory {
            errorHistory.removeFirst(errorHistory.count - maxErrorHistory)
        }
    }
    
    private func logError(_ error: AppError, context: ErrorContext) {
        let logMessage = """
        [ERROR] \(Date().ISO8601Format())
        Context: \(context.rawValue)
        Error: \(error.localizedDescription)
        Recovery: \(error.isRecoverable ? "Available" : "Not Available")
        Suggestion: \(error.recoverySuggestion ?? "None")
        """
        
        print(logMessage)
        
        // In production, send to crash reporting service
        #if DEBUG
        // Debug-only detailed logging
        if let underlyingError = error.underlyingError {
            print("Underlying error: \(underlyingError)")
        }
        #endif
    }
    
    // MARK: - Error Analytics
    
    func getErrorAnalytics() -> ErrorAnalytics {
        let now = Date()
        let last24Hours = now.addingTimeInterval(-86400) // 24 hours ago
        
        let recentErrors = errorHistory.filter { $0.timestamp > last24Hours }
        let errorsByType = Dictionary(grouping: recentErrors) { $0.error.category }
        let errorsByContext = Dictionary(grouping: recentErrors) { $0.context }
        
        return ErrorAnalytics(
            totalErrors: errorHistory.count,
            recentErrors: recentErrors.count,
            errorsByType: errorsByType.mapValues { $0.count },
            errorsByContext: errorsByContext.mapValues { $0.count },
            mostCommonError: findMostCommonError(in: recentErrors),
            averageErrorsPerDay: calculateAverageErrorsPerDay()
        )
    }
    
    private func findMostCommonError(in errors: [ErrorEvent]) -> ErrorCategory? {
        let errorCounts = Dictionary(grouping: errors) { $0.error.category }
        return errorCounts.max(by: { $0.value.count < $1.value.count })?.key
    }
    
    private func calculateAverageErrorsPerDay() -> Double {
        guard !errorHistory.isEmpty else { return 0 }
        
        let firstError = errorHistory.first!.timestamp
        let daysSinceFirst = Date().timeIntervalSince(firstError) / 86400
        return daysSinceFirst > 0 ? Double(errorHistory.count) / daysSinceFirst : Double(errorHistory.count)
    }
    
    // MARK: - User Interface Helpers
    
    func clearCurrentError() {
        currentError = nil
        showErrorAlert = false
    }
    
    func retryLastOperation() {
        guard let error = currentError else { return }
        
        if error.isRecoverable {
            attemptRecovery(for: error, context: .general)
        }
    }
}

// MARK: - App Error Types

enum AppError: LocalizedError, Equatable {
    case networkError(NetworkErrorType)
    case authenticationError(AuthErrorType)
    case audioError(AudioErrorType)
    case storageError(StorageErrorType)
    case persistenceError(PersistenceErrorType)
    case validationError(ValidationErrorType)
    case permissionError(PermissionErrorType)
    case systemError(SystemErrorType)
    case recoveryFailed(originalError: AppError, recoveryError: Error)
    case recoveryNotAvailable
    case recoveryTimeout
    case unknown(Error)
    
    static func from(_ error: Error, context: ErrorContext) -> AppError {
        switch error {
        case let networkError as NetworkError:
            return .networkError(NetworkErrorType(networkError))
        case let audioError as AudioServiceError:
            return .audioError(AudioErrorType(audioError))
        case let authError as AuthError:
            return .authenticationError(AuthErrorType(authError))
        case let persistenceError as PersistenceError:
            return .persistenceError(PersistenceErrorType(persistenceError))
        default:
            return .unknown(error)
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .networkError(let type):
            return type.description
        case .authenticationError(let type):
            return type.description
        case .audioError(let type):
            return type.description
        case .storageError(let type):
            return type.description
        case .persistenceError(let type):
            return type.description
        case .validationError(let type):
            return type.description
        case .permissionError(let type):
            return type.description
        case .systemError(let type):
            return type.description
        case .recoveryFailed(let originalError, _):
            return "Failed to recover from: \(originalError.localizedDescription)"
        case .recoveryNotAvailable:
            return "Automatic recovery is not available for this error"
        case .recoveryTimeout:
            return "Recovery attempt timed out"
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError(.networkUnavailable):
            return "Check your internet connection and try again."
        case .authenticationError(.tokenExpired):
            return "Please sign in again to continue."
        case .audioError(.permissionDenied):
            return "Go to Settings > Privacy & Security > Microphone to enable access."
        case .storageError(.insufficientSpace):
            return "Free up storage space and try again."
        case .persistenceError(.saveFailed):
            return "Your data couldn't be saved. Please try again."
        case .recoveryFailed:
            return "Please try again manually or contact support if the problem persists."
        default:
            return "Please try again. If the problem persists, contact support."
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .networkError(.networkUnavailable),
             .authenticationError(.tokenExpired),
             .storageError(.insufficientSpace),
             .persistenceError(.saveFailed):
            return true
        case .audioError(.permissionDenied),
             .permissionError:
            return true // Requires user action but recoverable
        case .recoveryFailed,
             .recoveryNotAvailable,
             .validationError,
             .systemError:
            return false
        case .unknown:
            return false
        default:
            return false
        }
    }
    
    var category: ErrorCategory {
        switch self {
        case .networkError:
            return .network
        case .authenticationError:
            return .authentication
        case .audioError:
            return .audio
        case .storageError:
            return .storage
        case .persistenceError:
            return .persistence
        case .validationError:
            return .validation
        case .permissionError:
            return .permission
        case .systemError:
            return .system
        case .recoveryFailed, .recoveryNotAvailable, .recoveryTimeout:
            return .recovery
        case .unknown:
            return .unknown
        }
    }
    
    var underlyingError: Error? {
        switch self {
        case .recoveryFailed(_, let recoveryError):
            return recoveryError
        case .unknown(let error):
            return error
        default:
            return nil
        }
    }
}

// MARK: - Error Type Enums

enum NetworkErrorType {
    case networkUnavailable
    case timeout
    case serverError
    case authenticationFailed
    case rateLimited
    case unknown
    
    init(_ networkError: NetworkError) {
        switch networkError {
        case .networkUnavailable:
            self = .networkUnavailable
        case .serverError:
            self = .serverError
        case .unauthorized:
            self = .authenticationFailed
        case .rateLimited:
            self = .rateLimited
        default:
            self = .unknown
        }
    }
    
    var description: String {
        switch self {
        case .networkUnavailable:
            return "No internet connection available"
        case .timeout:
            return "Request timed out"
        case .serverError:
            return "Server is temporarily unavailable"
        case .authenticationFailed:
            return "Authentication failed"
        case .rateLimited:
            return "Too many requests. Please wait and try again."
        case .unknown:
            return "Network error occurred"
        }
    }
}

enum AudioErrorType {
    case permissionDenied
    case deviceUnavailable
    case recordingFailed
    case playbackFailed
    case unknown
    
    init(_ audioError: AudioServiceError) {
        switch audioError {
        case .permissionDenied:
            self = .permissionDenied
        case .audioSessionUnavailable:
            self = .deviceUnavailable
        case .recordingFailed:
            self = .recordingFailed
        default:
            self = .unknown
        }
    }
    
    var description: String {
        switch self {
        case .permissionDenied:
            return "Microphone access is required"
        case .deviceUnavailable:
            return "Audio device is not available"
        case .recordingFailed:
            return "Recording failed"
        case .playbackFailed:
            return "Audio playback failed"
        case .unknown:
            return "Audio error occurred"
        }
    }
}

enum AuthErrorType {
    case tokenExpired
    case invalidCredentials
    case networkError
    case unknown
    
    init(_ authError: AuthError) {
        switch authError {
        case .tokenExpired:
            self = .tokenExpired
        case .invalidCredentials:
            self = .invalidCredentials
        case .networkError:
            self = .networkError
        default:
            self = .unknown
        }
    }
    
    var description: String {
        switch self {
        case .tokenExpired:
            return "Your session has expired"
        case .invalidCredentials:
            return "Invalid credentials"
        case .networkError:
            return "Authentication network error"
        case .unknown:
            return "Authentication error occurred"
        }
    }
}

enum StorageErrorType {
    case insufficientSpace
    case fileNotFound
    case accessDenied
    case corruptedData
    case unknown
    
    var description: String {
        switch self {
        case .insufficientSpace:
            return "Not enough storage space"
        case .fileNotFound:
            return "Required file not found"
        case .accessDenied:
            return "Storage access denied"
        case .corruptedData:
            return "Data is corrupted"
        case .unknown:
            return "Storage error occurred"
        }
    }
}

enum PersistenceErrorType {
    case saveFailed
    case fetchFailed
    case migrationFailed
    case encryptionFailed
    case unknown
    
    init(_ persistenceError: PersistenceError) {
        switch persistenceError {
        case .saveFailed:
            self = .saveFailed
        case .fetchFailed:
            self = .fetchFailed
        case .migrationFailed:
            self = .migrationFailed
        case .encryptionKeyNotFound:
            self = .encryptionFailed
        default:
            self = .unknown
        }
    }
    
    var description: String {
        switch self {
        case .saveFailed:
            return "Failed to save data"
        case .fetchFailed:
            return "Failed to load data"
        case .migrationFailed:
            return "Database migration failed"
        case .encryptionFailed:
            return "Data encryption failed"
        case .unknown:
            return "Database error occurred"
        }
    }
}

enum ValidationErrorType {
    case invalidInput
    case missingRequiredField
    case formatError
    case unknown
    
    var description: String {
        switch self {
        case .invalidInput:
            return "Invalid input provided"
        case .missingRequiredField:
            return "Required field is missing"
        case .formatError:
            return "Invalid format"
        case .unknown:
            return "Validation error occurred"
        }
    }
}

enum PermissionErrorType {
    case microphone
    case notifications
    case backgroundRefresh
    case unknown
    
    var description: String {
        switch self {
        case .microphone:
            return "Microphone permission required"
        case .notifications:
            return "Notification permission required"
        case .backgroundRefresh:
            return "Background app refresh required"
        case .unknown:
            return "Permission required"
        }
    }
}

enum SystemErrorType {
    case memoryWarning
    case backgroundProcessing
    case deviceLocked
    case unknown
    
    var description: String {
        switch self {
        case .memoryWarning:
            return "Low memory warning"
        case .backgroundProcessing:
            return "Background processing error"
        case .deviceLocked:
            return "Device is locked"
        case .unknown:
            return "System error occurred"
        }
    }
}

// MARK: - Supporting Types

enum ErrorContext: String, CaseIterable {
    case general = "general"
    case recording = "recording"
    case upload = "upload"
    case playback = "playback"
    case authentication = "authentication"
    case sync = "sync"
    case conversation = "conversation"
}

enum ErrorCategory: String, CaseIterable {
    case network = "network"
    case authentication = "authentication"
    case audio = "audio"
    case storage = "storage"
    case persistence = "persistence"
    case validation = "validation"
    case permission = "permission"
    case system = "system"
    case recovery = "recovery"
    case unknown = "unknown"
}

struct ErrorEvent {
    let error: AppError
    let context: ErrorContext
    let timestamp: Date
}

struct ErrorAnalytics {
    let totalErrors: Int
    let recentErrors: Int
    let errorsByType: [ErrorCategory: Int]
    let errorsByContext: [ErrorContext: Int]
    let mostCommonError: ErrorCategory?
    let averageErrorsPerDay: Double
}

// MARK: - SwiftUI Error Handling Views

struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorHandler = ErrorHandlingService.shared
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $errorHandler.showErrorAlert) {
                Button("OK") {
                    errorHandler.clearCurrentError()
                }
                
                if let error = errorHandler.currentError, error.isRecoverable {
                    Button("Retry") {
                        errorHandler.retryLastOperation()
                    }
                }
            } message: {
                if let error = errorHandler.currentError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.localizedDescription)
                        
                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
    }
}

extension View {
    func withErrorHandling() -> some View {
        self.modifier(ErrorAlertModifier())
    }
}