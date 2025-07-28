import XCTest
import AVFoundation
import Combine
@testable import TimeCapsule

final class AudioServiceTests: XCTestCase {
    
    var audioService: AudioService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        audioService = AudioService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        audioService = nil
        cancellables = nil
    }
    
    func testInitialState() throws {
        XCTAssertFalse(audioService.isRecording)
        XCTAssertEqual(audioService.meterLevel, 0.0)
    }
    
    func testMeterLevelPublisher() throws {
        let expectation = expectation(description: "Meter level published")
        var receivedValues: [Double] = []
        
        audioService.meterLevelPublisher
            .sink { level in
                receivedValues.append(level)
                if receivedValues.count >= 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertFalse(receivedValues.isEmpty)
    }
    
    func testPermissionRequest() async throws {
        let hasPermission = await audioService.requestPermissions()
        
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            XCTAssertTrue(hasPermission)
        case .denied:
            XCTAssertFalse(hasPermission)
        case .undetermined:
            break
        @unknown default:
            XCTAssertFalse(hasPermission)
        }
    }
    
    func testCancelRecording() throws {
        audioService.cancelRecording()
        XCTAssertFalse(audioService.isRecording)
        XCTAssertEqual(audioService.meterLevel, 0.0)
    }
    
    func testRecordingStateAfterCancel() throws {
        audioService.cancelRecording()
        
        XCTAssertFalse(audioService.isRecording)
        XCTAssertEqual(audioService.meterLevel, 0.0)
    }
    
    func testAudioServiceError() throws {
        let permissionError = AudioServiceError.permissionDenied
        XCTAssertEqual(permissionError.errorDescription, "Microphone permission denied")
        
        let recordingError = AudioServiceError.recordingFailed
        XCTAssertEqual(recordingError.errorDescription, "Failed to start recording")
        
        let notRecordingError = AudioServiceError.notRecording
        XCTAssertEqual(notRecordingError.errorDescription, "Not currently recording")
        
        let notFoundError = AudioServiceError.recordingNotFound
        XCTAssertEqual(notFoundError.errorDescription, "Recording file not found")
    }
    
    @MainActor
    func testStopRecordingWhenNotRecording() async throws {
        do {
            _ = try await audioService.stopRecording()
            XCTFail("Should throw error when not recording")
        } catch let error as AudioServiceError {
            XCTAssertEqual(error, AudioServiceError.notRecording)
        }
    }
}

final class MockAudioService: AudioServiceProtocol {
    @Published private(set) var isRecording = false
    @Published private(set) var meterLevel: Double = 0.0
    
    var meterLevelPublisher: AnyPublisher<Double, Never> {
        $meterLevel.eraseToAnyPublisher()
    }
    
    var shouldGrantPermissions = true
    var shouldFailRecording = false
    
    func requestPermissions() async -> Bool {
        return shouldGrantPermissions
    }
    
    func startRecording() async throws {
        if shouldFailRecording {
            throw AudioServiceError.recordingFailed
        }
        isRecording = true
    }
    
    func stopRecording() async throws -> LocalRecording {
        guard isRecording else {
            throw AudioServiceError.notRecording
        }
        
        isRecording = false
        meterLevel = 0.0
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_recording.wav")
        
        return LocalRecording(
            id: UUID(),
            url: tempURL,
            duration: 5.0,
            fileSize: 1024,
            createdAt: Date()
        )
    }
    
    func cancelRecording() {
        isRecording = false
        meterLevel = 0.0
    }
}