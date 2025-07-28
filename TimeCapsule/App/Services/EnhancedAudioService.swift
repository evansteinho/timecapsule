import Foundation
import AVFoundation
import Combine

/// Enhanced AudioService with performance optimizations and background handling
final class EnhancedAudioService: AudioServiceProtocol {
    @Published var meterLevel: Double = 0.0
    @Published var peakLevel: Double = 0.0
    @Published var isRecording: Bool = false
    
    var meterLevelPublisher: Published<Double>.Publisher { $meterLevel }
    
    private var audioRecorder: AVAudioRecorder?
    private var audioSession = AVAudioSession.sharedInstance()
    private var meterTimer: Timer?
    private var hasPermissions = false
    
    // Audio interruption handling
    private var wasRecordingBeforeInterruption = false
    private var cancellables = Set<AnyCancellable>()
    
    // Performance optimizations
    private let audioQueue = DispatchQueue(label: "audio.processing", qos: .userInitiated)
    private let meterUpdateInterval: TimeInterval = 0.15 // Optimized for battery life
    private let maxRecordingDuration: TimeInterval = 600 // 10 minutes
    
    init() {
        setupAudioSession()
        setupInterruptionHandling()
        setupBackgroundHandling()
    }
    
    deinit {
        cleanupAudio()
    }
    
    // MARK: - AudioServiceProtocol Implementation
    
    func requestPermissions() async -> Bool {
        let status = await audioSession.requestRecordPermission()
        hasPermissions = status
        return status
    }
    
    func startRecording() async throws {
        guard hasPermissions else {
            throw AudioServiceError.permissionDenied
        }
        
        guard !isRecording else {
            throw AudioServiceError.alreadyRecording
        }
        
        try await setupRecorder()
        
        guard let recorder = audioRecorder else {
            throw AudioServiceError.setupFailed
        }
        
        let success = recorder.record()
        guard success else {
            throw AudioServiceError.recordingFailed
        }
        
        await MainActor.run {
            isRecording = true
        }
        
        startMeterTimer()
        scheduleRecordingTimeLimit()
    }
    
    func stopRecording() async throws -> LocalRecording {
        guard let recorder = audioRecorder, isRecording else {
            throw AudioServiceError.notRecording
        }
        
        stopMeterTimer()
        recorder.stop()
        
        await MainActor.run {
            isRecording = false
            meterLevel = 0.0
            peakLevel = 0.0
        }
        
        let fileURL = recorder.url
        let duration = recorder.currentTime
        
        // Validate recording
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AudioServiceError.fileNotFound
        }
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
        
        audioRecorder = nil
        
        return LocalRecording(
            id: UUID(),
            url: fileURL,
            duration: duration,
            fileSize: fileSize,
            createdAt: Date()
        )
    }
    
    func cancelRecording() {
        guard let recorder = audioRecorder else { return }
        
        stopMeterTimer()
        recorder.stop()
        
        // Clean up the file
        try? FileManager.default.removeItem(at: recorder.url)
        
        Task { @MainActor in
            isRecording = false
            meterLevel = 0.0
            peakLevel = 0.0
        }
        
        audioRecorder = nil
    }
    
    // MARK: - Enhanced Audio Session Setup
    
    private func setupAudioSession() {
        do {
            // Use .voiceChat mode for better voice processing
            try audioSession.setCategory(.playAndRecord, 
                                       mode: .voiceChat, 
                                       options: [.defaultToSpeaker, 
                                               .allowBluetooth, 
                                               .allowBluetoothA2DP])
            
            // Set preferred sample rate to match recording format
            try audioSession.setPreferredSampleRate(16000.0)
            
            // Optimize buffer size for low latency
            try audioSession.setPreferredIOBufferDuration(0.02) // 20ms buffer
            
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func setupRecorder() async throws {
        let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                    in: .userDomainMask)[0]
        let audioDirectory = documentsPath.appendingPathComponent("Audio")
        
        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(at: audioDirectory, 
                                              withIntermediateDirectories: true)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "\(dateFormatter.string(from: Date())).wav"
        let fileURL = audioDirectory.appendingPathComponent(fileName)
        
        // Optimized settings for 16 kHz mono WAV
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
    }
    
    // MARK: - Enhanced Meter Level Processing
    
    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: meterUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateMeterLevels()
        }
    }
    
    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }
    
    private func updateMeterLevels() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        
        audioQueue.async { [weak self] in
            recorder.updateMeters()
            
            let averagePower = recorder.averagePower(forChannel: 0)
            let peakPower = recorder.peakPower(forChannel: 0)
            
            // Improved logarithmic scaling for better visual representation
            let averageNormalized = pow(10.0, (0.05 * averagePower))
            let peakNormalized = pow(10.0, (0.05 * peakPower))
            
            Task { @MainActor in
                self?.meterLevel = averageNormalized
                self?.peakLevel = peakNormalized
            }
        }
    }
    
    // MARK: - Recording Duration Management
    
    private func scheduleRecordingTimeLimit() {
        Task {
            try await Task.sleep(nanoseconds: UInt64(maxRecordingDuration * 1_000_000_000))
            
            if isRecording {
                await MainActor.run {
                    // Notify about time limit reached
                    NotificationCenter.default.post(
                        name: .recordingTimeLimitReached,
                        object: nil
                    )
                }
                
                try? await stopRecording()
            }
        }
    }
    
    // MARK: - Audio Interruption Handling
    
    private func setupInterruptionHandling() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                self?.handleRouteChange(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            wasRecordingBeforeInterruption = isRecording
            if isRecording {
                cancelRecording()
            }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) && wasRecordingBeforeInterruption {
                // Notify UI that recording was interrupted and can be resumed
                NotificationCenter.default.post(
                    name: .recordingInterruptionEnded,
                    object: nil
                )
            }
        @unknown default:
            break
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Handle device disconnection (e.g., headphones unplugged)
            if isRecording {
                // Optionally pause recording or show warning
                NotificationCenter.default.post(
                    name: .audioDeviceDisconnected,
                    object: nil
                )
            }
        default:
            break
        }
    }
    
    // MARK: - Background Handling
    
    private func setupBackgroundHandling() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppDidEnterBackground()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppWillEnterForeground()
            }
            .store(in: &cancellables)
    }
    
    private func handleAppDidEnterBackground() {
        // Recording can continue in background with proper background modes
        // But we should optimize for battery usage
        if isRecording {
            // Reduce meter update frequency in background
            stopMeterTimer()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.updateMeterLevels()
            }
        }
    }
    
    private func handleAppWillEnterForeground() {
        // Restore normal meter update frequency
        if isRecording {
            stopMeterTimer()
            startMeterTimer()
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanupAudio() {
        stopMeterTimer()
        audioRecorder?.stop()
        audioRecorder = nil
        
        try? audioSession.setActive(false)
    }
}

// MARK: - Enhanced Error Types

enum AudioServiceError: LocalizedError {
    case permissionDenied
    case setupFailed
    case recordingFailed
    case alreadyRecording
    case notRecording
    case fileNotFound
    case recordingTooShort
    case recordingTooLong
    case diskSpaceInsufficient
    case audioSessionUnavailable
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required to record voice capsules."
        case .setupFailed:
            return "Failed to setup audio recording. Please try again."
        case .recordingFailed:
            return "Recording failed to start. Please check your microphone."
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "No recording in progress."
        case .fileNotFound:
            return "Recording file was not found."
        case .recordingTooShort:
            return "Recording is too short. Please record for at least 1 second."
        case .recordingTooLong:
            return "Recording exceeded maximum duration of 10 minutes."
        case .diskSpaceInsufficient:
            return "Insufficient storage space for recording."
        case .audioSessionUnavailable:
            return "Audio system is currently unavailable."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Go to Settings > Privacy & Security > Microphone and enable access for Time-Capsule."
        case .setupFailed, .recordingFailed:
            return "Make sure no other apps are using the microphone and try again."
        case .diskSpaceInsufficient:
            return "Free up some storage space and try again."
        default:
            return nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let recordingTimeLimitReached = Notification.Name("recordingTimeLimitReached")
    static let recordingInterruptionEnded = Notification.Name("recordingInterruptionEnded")
    static let audioDeviceDisconnected = Notification.Name("audioDeviceDisconnected")
}