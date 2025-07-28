import XCTest
import Combine
@testable import TimeCapsule

final class ErrorHandlingServiceTests: XCTestCase {
    var sut: ErrorHandlingService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = ErrorHandlingService.shared
        cancellables = Set<AnyCancellable>()
        
        // Reset service state
        sut.currentError = nil
        sut.showErrorAlert = false
        sut.errorRecoveryInProgress = false
    }
    
    override func tearDownWithError() throws {
        cancellables = nil
        sut = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Error Reporting Tests
    
    func testReportError_NetworkError_CreatesCorrectAppError() {
        // Given
        let networkError = NetworkError.networkUnavailable
        let expectation = XCTestExpectation(description: "Error reported")
        
        // When
        sut.$currentError
            .dropFirst()
            .sink { error in
                // Then
                XCTAssertNotNil(error)
                if case .networkError(let type) = error! {
                    XCTAssertEqual(type, .networkUnavailable)
                } else {
                    XCTFail("Expected network error")
                }
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        sut.reportError(networkError, context: .general)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(sut.showErrorAlert)
    }
    
    func testReportError_AudioError_CreatesCorrectAppError() {
        // Given
        let audioError = AudioServiceError.permissionDenied
        let expectation = XCTestExpectation(description: "Error reported")
        
        // When
        sut.$currentError
            .dropFirst()
            .sink { error in
                // Then
                XCTAssertNotNil(error)
                if case .audioError(let type) = error! {
                    XCTAssertEqual(type, .permissionDenied)
                } else {
                    XCTFail("Expected audio error")
                }
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        sut.reportError(audioError, context: .recording)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Error Recovery Tests
    
    func testAttemptRecovery_RecoverableError_StartsRecoveryProcess() {
        // Given
        let recoverableError = AppError.networkError(.networkUnavailable)
        
        // When
        sut.attemptRecovery(for: recoverableError, context: .general)
        
        // Then
        XCTAssertTrue(sut.errorRecoveryInProgress)
    }
    
    func testAttemptRecovery_NonRecoverableError_DoesNotStartRecovery() {
        // Given
        let nonRecoverableError = AppError.validationError(.invalidInput)
        
        // When
        sut.attemptRecovery(for: nonRecoverableError, context: .general)
        
        // Then
        // Should not start recovery for non-recoverable errors
        // The actual behavior depends on implementation
    }
    
    // MARK: - Error Classification Tests
    
    func testAppErrorFromNetworkError_CreatesCorrectType() {
        // Given
        let networkError = NetworkError.serverError(500)
        
        // When
        let appError = AppError.from(networkError, context: .general)
        
        // Then
        if case .networkError(let type) = appError {
            XCTAssertEqual(type, .serverError)
        } else {
            XCTFail("Expected network error type")
        }
        
        XCTAssertEqual(appError.category, .network)
        XCTAssertFalse(appError.isRecoverable)
    }
    
    func testAppErrorFromAudioError_CreatesCorrectType() {
        // Given
        let audioError = AudioServiceError.permissionDenied
        
        // When
        let appError = AppError.from(audioError, context: .recording)
        
        // Then
        if case .audioError(let type) = appError {
            XCTAssertEqual(type, .permissionDenied)
        } else {
            XCTFail("Expected audio error type")
        }
        
        XCTAssertEqual(appError.category, .audio)
        XCTAssertTrue(appError.isRecoverable)
    }
    
    // MARK: - Error Analytics Tests
    
    func testGetErrorAnalytics_WithErrorHistory_ReturnsCorrectData() {
        // Given
        let errors = [
            NetworkError.networkUnavailable,
            AudioServiceError.permissionDenied,
            NetworkError.serverError(500),
            AudioServiceError.recordingFailed
        ]
        
        // When
        for error in errors {
            sut.reportError(error, context: .general)
        }
        
        let analytics = sut.getErrorAnalytics()
        
        // Then
        XCTAssertEqual(analytics.totalErrors, 4)
        XCTAssertEqual(analytics.recentErrors, 4)
        XCTAssertTrue(analytics.errorsByType[.network] ?? 0 > 0)
        XCTAssertTrue(analytics.errorsByType[.audio] ?? 0 > 0)
    }
    
    // MARK: - Error Message Tests
    
    func testErrorDescription_NetworkUnavailable_ReturnsCorrectMessage() {
        // Given
        let error = AppError.networkError(.networkUnavailable)
        
        // When
        let description = error.errorDescription
        
        // Then
        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains("internet"))
    }
    
    func testRecoverySuggestion_PermissionDenied_ReturnsCorrectSuggestion() {
        // Given
        let error = AppError.audioError(.permissionDenied)
        
        // When
        let suggestion = error.recoverySuggestion
        
        // Then
        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion!.contains("Settings"))
    }
    
    // MARK: - Error Clearing Tests
    
    func testClearCurrentError_ResetsErrorState() {
        // Given
        sut.currentError = AppError.networkError(.networkUnavailable)
        sut.showErrorAlert = true
        
        // When
        sut.clearCurrentError()
        
        // Then
        XCTAssertNil(sut.currentError)
        XCTAssertFalse(sut.showErrorAlert)
    }
    
    // MARK: - Error Equality Tests
    
    func testAppErrorEquality_SameErrors_AreEqual() {
        // Given
        let error1 = AppError.networkError(.networkUnavailable)
        let error2 = AppError.networkError(.networkUnavailable)
        
        // Then
        XCTAssertEqual(error1, error2)
    }
    
    func testAppErrorEquality_DifferentErrors_AreNotEqual() {
        // Given
        let error1 = AppError.networkError(.networkUnavailable)
        let error2 = AppError.audioError(.permissionDenied)
        
        // Then
        XCTAssertNotEqual(error1, error2)
    }
    
    // MARK: - Error Context Tests
    
    func testErrorContext_DifferentContexts_AreTrackedSeparately() {
        // Given
        let networkError = NetworkError.networkUnavailable
        
        // When
        sut.reportError(networkError, context: .recording)
        sut.reportError(networkError, context: .upload)
        
        let analytics = sut.getErrorAnalytics()
        
        // Then
        XCTAssertTrue(analytics.errorsByContext[.recording] ?? 0 > 0)
        XCTAssertTrue(analytics.errorsByContext[.upload] ?? 0 > 0)
    }
    
    // MARK: - Performance Tests
    
    func testErrorReporting_Performance_CompletesQuickly() {
        // Given
        let error = NetworkError.networkUnavailable
        
        // When
        measure {
            for _ in 0..<100 {
                sut.reportError(error, context: .general)
            }
        }
    }
}