import Foundation
import AVFoundation
import Combine

/// Protocol defining audio recording capabilities for the TimeCapsule app
/// 
/// This service handles high-quality audio recording at 16 kHz mono WAV format
/// with real-time audio level metering and reactive state updates.
protocol AudioServiceProtocol {
    var isRecording: Bool { get }
    var meterLevel: Double { get }
    var meterLevelPublisher: AnyPublisher<Double, Never> { get }
    
    func requestPermissions() async -> Bool
    func startRecording() async throws
    func stopRecording() async throws -> LocalRecording
    func cancelRecording()
}

/// Core audio recording service for TimeCapsule voice capsules
///
/// Features:
/// - Records 16 kHz mono WAV files optimized for speech
/// - Real-time audio level metering for waveform visualization  
/// - Automatic file management in secure Application Support directory
/// - Reactive state updates via Combine publishers
/// - Comprehensive error handling and permission management
final class AudioService: NSObject, ObservableObject, AudioServiceProtocol {
    @Published private(set) var isRecording = false
    @Published private(set) var meterLevel: Double = 0.0
    
    var meterLevelPublisher: AnyPublisher<Double, Never> {
        $meterLevel.eraseToAnyPublisher()
    }
    
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var currentRecordingURL: URL?
    private let audioSession = AVAudioSession.sharedInstance()
    
    private var audioDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
        let audioPath = documentsPath.appendingPathComponent("Audio")
        
        try? FileManager.default.createDirectory(at: audioPath,
                                               withIntermediateDirectories: true)
        return audioPath
    }
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        meterTimer?.invalidate()
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func requestPermissions() async -> Bool {
        switch audioSession.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                audioSession.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
    
    @MainActor
    func startRecording() async throws {
        guard !isRecording else { return }
        
        let hasPermission = await requestPermissions()
        guard hasPermission else {
            throw AudioServiceError.permissionDenied
        }
        
        let timestamp = DateFormatter.audioFileFormatter.string(from: Date())
        let filename = "\(timestamp).wav"
        let url = audioDirectory.appendingPathComponent(filename)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            guard audioRecorder?.record() == true else {
                throw AudioServiceError.recordingFailed
            }
            
            currentRecordingURL = url
            isRecording = true
            startMeterTimer()
            
        } catch {
            throw AudioServiceError.recordingFailed
        }
    }
    
    @MainActor
    func stopRecording() async throws -> LocalRecording {
        guard isRecording, let recorder = audioRecorder, let url = currentRecordingURL else {
            throw AudioServiceError.notRecording
        }
        
        stopMeterTimer()
        recorder.stop()
        isRecording = false
        meterLevel = 0.0
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw AudioServiceError.recordingNotFound
        }
        
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let duration = recorder.currentTime
        
        let recording = LocalRecording(
            id: UUID(),
            url: url,
            duration: duration,
            fileSize: fileSize,
            createdAt: Date()
        )
        
        cleanup()
        return recording
    }
    
    func cancelRecording() {
        guard isRecording else { return }
        
        stopMeterTimer()
        audioRecorder?.stop()
        
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        cleanup()
    }
    
    private func cleanup() {
        audioRecorder = nil
        currentRecordingURL = nil
        isRecording = false
        meterLevel = 0.0
    }
    
    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateMeterLevel()
        }
    }
    
    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }
    
    private func updateMeterLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        
        let normalizedLevel = max(0.0, min(1.0, (level + 80.0) / 80.0))
        
        DispatchQueue.main.async {
            self.meterLevel = normalizedLevel
        }
    }
}

extension AudioService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            DispatchQueue.main.async {
                self.cleanup()
            }
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async {
            self.cleanup()
        }
    }
}

enum AudioServiceError: LocalizedError {
    case permissionDenied
    case recordingFailed
    case notRecording
    case recordingNotFound
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .recordingFailed:
            return "Failed to start recording"
        case .notRecording:
            return "Not currently recording"
        case .recordingNotFound:
            return "Recording file not found"
        }
    }
}

private extension DateFormatter {
    static let audioFileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}