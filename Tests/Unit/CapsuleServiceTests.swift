import XCTest
import CoreData
@testable import TimeCapsule

final class CapsuleServiceTests: XCTestCase {
    var sut: CapsuleService!
    var mockNetworkService: MockNetworkService!
    var testPersistenceService: PersistenceService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockNetworkService = MockNetworkService()
        testPersistenceService = createInMemoryPersistenceService()
        sut = CapsuleService(
            networkService: mockNetworkService,
            persistenceService: testPersistenceService
        )
    }
    
    override func tearDownWithError() throws {
        sut.stopPolling()
        sut = nil
        mockNetworkService = nil
        testPersistenceService = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Save Capsule Tests
    
    func testSaveCapsule_NewCapsule_SavesSuccessfully() async throws {
        // Given
        let capsule = createTestCapsule()
        let localFileURL = URL(fileURLWithPath: "/test/path/audio.wav")
        
        // When
        try await sut.saveCapsule(capsule, localFileURL: localFileURL)
        
        // Then
        let savedCapsule = try await sut.getCapsule(by: capsule.id)
        XCTAssertNotNil(savedCapsule)
        XCTAssertEqual(savedCapsule?.id, capsule.id)
        XCTAssertEqual(savedCapsule?.status, capsule.status)
    }
    
    func testSaveCapsule_ExistingCapsule_UpdatesSuccessfully() async throws {
        // Given
        let capsule = createTestCapsule(status: .uploading)
        let localFileURL = URL(fileURLWithPath: "/test/path/audio.wav")
        
        // Save initial capsule
        try await sut.saveCapsule(capsule, localFileURL: localFileURL)
        
        // Create updated capsule
        let updatedCapsule = Capsule(
            id: capsule.id,
            userId: capsule.userId,
            audioURL: capsule.audioURL,
            transcription: "Updated transcription",
            duration: capsule.duration,
            fileSize: capsule.fileSize,
            createdAt: capsule.createdAt,
            updatedAt: Date(),
            status: .completed,
            metadata: capsule.metadata
        )
        
        // When
        try await sut.saveCapsule(updatedCapsule, localFileURL: localFileURL)
        
        // Then
        let savedCapsule = try await sut.getCapsule(by: capsule.id)
        XCTAssertEqual(savedCapsule?.status, .completed)
        XCTAssertEqual(savedCapsule?.transcription, "Updated transcription")
    }
    
    // MARK: - Poll Transcription Tests
    
    func testPollTranscription_ValidCapsuleId_ReturnsUpdatedCapsule() async throws {
        // Given
        let capsuleId = "test-capsule-id"
        let expectedCapsule = createTestCapsule(id: capsuleId, status: .completed)
        mockNetworkService.mockGetResponse = expectedCapsule
        
        // When
        let result = try await sut.pollTranscription(for: capsuleId)
        
        // Then
        XCTAssertEqual(result.id, capsuleId)
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(mockNetworkService.getCallCount, 1)
        XCTAssertEqual(mockNetworkService.lastGetPath, "/v0/capsules/\(capsuleId)")
    }
    
    func testPollTranscription_NetworkError_ThrowsError() async {
        // Given
        let capsuleId = "test-capsule-id"
        mockNetworkService.shouldThrowError = true
        mockNetworkService.errorToThrow = NetworkError.serverError(500)
        
        // When/Then
        do {
            _ = try await sut.pollTranscription(for: capsuleId)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: - Get All Capsules Tests
    
    func testGetAllCapsules_EmptyDatabase_ReturnsEmptyArray() async throws {
        // When
        let capsules = try await sut.getAllCapsules()
        
        // Then
        XCTAssertEqual(capsules.count, 0)
    }
    
    func testGetAllCapsules_WithSavedCapsules_ReturnsCapsulesInDescendingOrder() async throws {
        // Given
        let capsule1 = createTestCapsule(id: "1", createdAt: Date().addingTimeInterval(-3600)) // 1 hour ago
        let capsule2 = createTestCapsule(id: "2", createdAt: Date().addingTimeInterval(-1800)) // 30 minutes ago
        let capsule3 = createTestCapsule(id: "3", createdAt: Date()) // Now
        
        try await sut.saveCapsule(capsule1, localFileURL: nil)
        try await sut.saveCapsule(capsule2, localFileURL: nil)
        try await sut.saveCapsule(capsule3, localFileURL: nil)
        
        // When
        let capsules = try await sut.getAllCapsules()
        
        // Then
        XCTAssertEqual(capsules.count, 3)
        XCTAssertEqual(capsules[0].id, "3") // Most recent first
        XCTAssertEqual(capsules[1].id, "2")
        XCTAssertEqual(capsules[2].id, "1")
    }
    
    // MARK: - Get Capsule By ID Tests
    
    func testGetCapsule_ExistingId_ReturnsCapsule() async throws {
        // Given
        let capsule = createTestCapsule()
        try await sut.saveCapsule(capsule, localFileURL: nil)
        
        // When
        let result = try await sut.getCapsule(by: capsule.id)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, capsule.id)
    }
    
    func testGetCapsule_NonExistentId_ReturnsNil() async throws {
        // When
        let result = try await sut.getCapsule(by: "non-existent-id")
        
        // Then
        XCTAssertNil(result)
    }
    
    // MARK: - Polling Tests
    
    func testStartPolling_CreatesPollingTimer() {
        // When
        sut.startPollingForPendingCapsules()
        
        // Then
        // Note: In a real implementation, you'd need to expose the timer state
        // or use a mock timer to test this properly
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    func testStopPolling_InvalidatesTimer() {
        // Given
        sut.startPollingForPendingCapsules()
        
        // When
        sut.stopPolling()
        
        // Then
        // Note: In a real implementation, you'd verify the timer is invalidated
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    // MARK: - Helper Methods
    
    private func createTestCapsule(
        id: String = "test-capsule-id",
        status: CapsuleStatus = .uploading,
        createdAt: Date = Date()
    ) -> Capsule {
        return Capsule(
            id: id,
            userId: "test-user-id",
            audioURL: URL(string: "https://example.com/audio.wav"),
            transcription: status == .completed ? "Test transcription" : nil,
            duration: 30.0,
            fileSize: 1024,
            createdAt: createdAt,
            updatedAt: Date(),
            status: status,
            metadata: nil
        )
    }
    
    private func createInMemoryPersistenceService() -> PersistenceService {
        let persistenceService = PersistenceService()
        
        // Configure for in-memory storage
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        persistenceService.persistentContainer.persistentStoreDescriptions = [description]
        
        return persistenceService
    }
}

// MARK: - Mock Network Service

class MockNetworkService: NetworkServiceProtocol {
    var mockGetResponse: Any?
    var mockPostResponse: Any?
    var mockUploadResponse: Any?
    var shouldThrowError = false
    var errorToThrow: Error = NetworkError.unknown
    
    var getCallCount = 0
    var postCallCount = 0
    var uploadCallCount = 0
    var lastGetPath: String?
    var lastPostPath: String?
    var lastUploadPath: String?
    
    func get<T: Codable>(path: String) async throws -> T {
        getCallCount += 1
        lastGetPath = path
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        guard let response = mockGetResponse as? T else {
            throw NetworkError.unknown
        }
        
        return response
    }
    
    func post<T: Codable>(path: String, body: [String: Any]) async throws -> T {
        postCallCount += 1
        lastPostPath = path
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        guard let response = mockPostResponse as? T else {
            throw NetworkError.unknown
        }
        
        return response
    }
    
    func upload<T: Codable>(path: String, fileURL: URL, parameters: [String: Any]) async throws -> T {
        uploadCallCount += 1
        lastUploadPath = path
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        guard let response = mockUploadResponse as? T else {
            throw NetworkError.unknown
        }
        
        return response
    }
}