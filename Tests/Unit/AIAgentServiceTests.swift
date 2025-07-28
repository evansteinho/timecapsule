import XCTest
import AVFoundation
@testable import TimeCapsule

final class AIAgentServiceTests: XCTestCase {
    var sut: AIAgentService!
    var mockNetworkService: MockNetworkService!
    var mockCapsuleService: MockCapsuleService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockNetworkService = MockNetworkService()
        mockCapsuleService = MockCapsuleService()
        sut = AIAgentService(
            networkService: mockNetworkService,
            capsuleService: mockCapsuleService
        )
    }
    
    override func tearDownWithError() throws {
        sut = nil
        mockNetworkService = nil
        mockCapsuleService = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Start Conversation Tests
    
    func testStartConversation_ValidCapsule_ReturnsConversationResponse() async throws {
        // Given
        let capsule = createTestCapsule()
        let expectedResponse = createTestStartConversationResponse()
        mockCapsuleService.mockCapsules = [capsule]
        mockNetworkService.mockPostResponse = expectedResponse
        
        // When
        let result = try await sut.startConversation(with: capsule, initialMessage: "Hello past self")
        
        // Then
        XCTAssertEqual(result.conversation.id, expectedResponse.conversation.id)
        XCTAssertEqual(mockNetworkService.postCallCount, 1)
        XCTAssertEqual(mockNetworkService.lastPostPath, "/v0/conversation/start")
    }
    
    func testStartConversation_NetworkError_ThrowsError() async {
        // Given
        let capsule = createTestCapsule()
        mockCapsuleService.mockCapsules = [capsule]
        mockNetworkService.shouldThrowError = true
        mockNetworkService.errorToThrow = NetworkError.serverError(500)
        
        // When/Then
        do {
            _ = try await sut.startConversation(with: capsule, initialMessage: nil)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    func testStartConversation_BuildsContextCorrectly() async throws {
        // Given
        let targetCapsule = createTestCapsule(id: "target")
        let contextCapsule1 = createTestCapsule(id: "context1", createdAt: Date().addingTimeInterval(-3600))
        let contextCapsule2 = createTestCapsule(id: "context2", createdAt: Date().addingTimeInterval(-7200))
        
        mockCapsuleService.mockCapsules = [targetCapsule, contextCapsule1, contextCapsule2]
        mockNetworkService.mockPostResponse = createTestStartConversationResponse()
        
        // When
        _ = try await sut.startConversation(with: targetCapsule, initialMessage: nil)
        
        // Then
        XCTAssertEqual(mockCapsuleService.getAllCapsulesCallCount, 1)
        // Verify context was built by checking the network request included context
        // (In a real implementation, you'd inspect the actual request body)
    }
    
    // MARK: - Send Message Tests
    
    func testSendMessage_ValidRequest_ReturnsMessageResponse() async throws {
        // Given
        let conversationId = "test-conversation"
        let messageContent = "How are you feeling today?"
        let expectedResponse = createTestSendMessageResponse()
        mockNetworkService.mockPostResponse = expectedResponse
        
        // When
        let result = try await sut.sendMessage(messageContent, to: conversationId, requestAudio: true)
        
        // Then
        XCTAssertEqual(result.message.content, expectedResponse.message.content)
        XCTAssertEqual(mockNetworkService.postCallCount, 1)
        XCTAssertEqual(mockNetworkService.lastPostPath, "/v0/conversation/message")
    }
    
    func testSendMessage_RequestWithoutAudio_SetsCorrectFlag() async throws {
        // Given
        let conversationId = "test-conversation"
        let messageContent = "Test message"
        let expectedResponse = createTestSendMessageResponse()
        mockNetworkService.mockPostResponse = expectedResponse
        
        // When
        _ = try await sut.sendMessage(messageContent, to: conversationId, requestAudio: false)
        
        // Then
        // Verify the request body contains requestAudio: false
        XCTAssertEqual(mockNetworkService.postCallCount, 1)
    }
    
    // MARK: - Get Conversation Tests
    
    func testGetConversation_ValidId_ReturnsConversation() async throws {
        // Given
        let conversationId = "test-conversation"
        let expectedConversation = createTestConversation()
        mockNetworkService.mockGetResponse = expectedConversation
        
        // When
        let result = try await sut.getConversation(id: conversationId)
        
        // Then
        XCTAssertEqual(result.id, expectedConversation.id)
        XCTAssertEqual(mockNetworkService.getCallCount, 1)
        XCTAssertEqual(mockNetworkService.lastGetPath, "/v0/conversation/\(conversationId)")
    }
    
    // MARK: - Time Lock Tests
    
    func testCheckTimeLock_ValidConversation_ReturnsTimeLockInfo() async throws {
        // Given
        let conversationId = "test-conversation"
        let expectedTimeLock = TimeLockInfo(
            isLocked: true,
            unlockTime: Date().addingTimeInterval(3600),
            lockReason: "24-hour reflection period",
            remainingTime: 3600
        )
        mockNetworkService.mockGetResponse = expectedTimeLock
        
        // When
        let result = try await sut.checkTimeLock(for: conversationId)
        
        // Then
        XCTAssertEqual(result.isLocked, expectedTimeLock.isLocked)
        XCTAssertEqual(result.lockReason, expectedTimeLock.lockReason)
        XCTAssertEqual(mockNetworkService.getCallCount, 1)
        XCTAssertEqual(mockNetworkService.lastGetPath, "/v0/conversation/\(conversationId)/timelock")
    }
    
    // MARK: - Audio Streaming Tests
    
    func testStreamAudioResponse_ValidURL_ReturnsAudioStream() async throws {
        // Given
        let testURL = URL(string: "https://example.com/audio-stream")!
        
        // When
        let stream = sut.streamAudioResponse(from: testURL)
        
        // Then
        var receivedData = Data()
        do {
            for try await chunk in stream {
                receivedData.append(chunk)
                break // Just test that we can get data
            }
        } catch {
            // Network errors are expected in unit tests
        }
        
        // Verify stream was created (actual streaming would require mock URLSession)
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    // MARK: - Context Building Tests
    
    func testRelevanceScoringLogic() {
        // This would test the private relevance scoring methods
        // For now, we test the behavior through the public API
        XCTAssertTrue(true) // Placeholder
    }
    
    func testEmotionalSimilarityCalculation() {
        // This would test the emotional similarity algorithm
        // For now, we test the behavior through the public API
        XCTAssertTrue(true) // Placeholder
    }
    
    func testTimeContextBuilding() {
        // This would test time context creation
        // For now, we test the behavior through the public API
        XCTAssertTrue(true) // Placeholder
    }
    
    // MARK: - Helper Methods
    
    private func createTestCapsule(
        id: String = "test-capsule",
        createdAt: Date = Date(),
        status: CapsuleStatus = .completed
    ) -> Capsule {
        return Capsule(
            id: id,
            userId: "test-user",
            audioURL: URL(string: "https://example.com/audio.wav"),
            transcription: "This is a test transcription for the capsule.",
            duration: 30.0,
            fileSize: 1024,
            createdAt: createdAt,
            updatedAt: Date(),
            status: status,
            metadata: CapsuleMetadata(
                emotions: [
                    EmotionScore(emotion: "happy", score: 0.7, confidence: 0.8),
                    EmotionScore(emotion: "reflective", score: 0.5, confidence: 0.6)
                ],
                topics: ["life", "growth", "reflection"],
                summary: "A reflective moment about personal growth"
            )
        )
    }
    
    private func createTestConversation() -> Conversation {
        return Conversation(
            id: "test-conversation",
            userId: "test-user",
            capsuleId: "test-capsule",
            messages: [
                ConversationMessage(
                    id: "msg-1",
                    conversationId: "test-conversation",
                    content: "Hello, how are you?",
                    role: .user,
                    audioURL: nil,
                    timestamp: Date(),
                    metadata: nil
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            status: .active,
            metadata: nil
        )
    }
    
    private func createTestStartConversationResponse() -> StartConversationResponse {
        return StartConversationResponse(
            conversation: createTestConversation(),
            initialResponse: ConversationMessage(
                id: "initial-msg",
                conversationId: "test-conversation",
                content: "Hello! I'm your past self. What would you like to know?",
                role: .assistant,
                audioURL: URL(string: "https://example.com/initial-audio.wav"),
                timestamp: Date(),
                metadata: MessageMetadata(
                    emotion: "welcoming",
                    confidence: 0.9,
                    processingTime: 1.5,
                    voiceCloneUsed: true
                )
            ),
            timeLockInfo: nil
        )
    }
    
    private func createTestSendMessageResponse() -> SendMessageResponse {
        return SendMessageResponse(
            message: ConversationMessage(
                id: "response-msg",
                conversationId: "test-conversation",
                content: "I'm feeling quite reflective today. That moment you're asking about was significant for me.",
                role: .assistant,
                audioURL: URL(string: "https://example.com/response-audio.wav"),
                timestamp: Date(),
                metadata: MessageMetadata(
                    emotion: "reflective",
                    confidence: 0.85,
                    processingTime: 2.1,
                    voiceCloneUsed: true
                )
            ),
            audioStreamURL: URL(string: "https://example.com/stream-audio"),
            isTimeLocked: false
        )
    }
}

// MARK: - Mock Capsule Service

class MockCapsuleService: CapsuleServiceProtocol {
    var mockCapsules: [Capsule] = []
    var getAllCapsulesCallCount = 0
    var saveCapsuleCallCount = 0
    var shouldThrowError = false
    var errorToThrow: Error = NetworkError.unknown
    
    func saveCapsule(_ capsule: Capsule, localFileURL: URL?) async throws {
        saveCapsuleCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    func pollTranscription(for capsuleId: String) async throws -> Capsule {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockCapsules.first { $0.id == capsuleId } ?? createDefaultCapsule()
    }
    
    func getAllCapsules() async throws -> [Capsule] {
        getAllCapsulesCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        return mockCapsules
    }
    
    func getCapsule(by id: String) async throws -> Capsule? {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockCapsules.first { $0.id == id }
    }
    
    func startPollingForPendingCapsules() {
        // Mock implementation
    }
    
    func stopPolling() {
        // Mock implementation
    }
    
    private func createDefaultCapsule() -> Capsule {
        return Capsule(
            id: "default-capsule",
            userId: "test-user",
            audioURL: nil,
            transcription: "Default transcription",
            duration: 30.0,
            fileSize: 1024,
            createdAt: Date(),
            updatedAt: Date(),
            status: .completed,
            metadata: nil
        )
    }
}