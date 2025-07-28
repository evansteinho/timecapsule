import Foundation
import Combine

enum UploadState {
    case idle
    case uploading(progress: Double)
    case completed(Capsule)
    case failed(Error)
}

/// Main view model for the voice recording interface
///
/// Coordinates between AudioService, AuthService, and AudioUploadService
/// to provide a seamless recording and upload experience. Handles:
/// - Audio recording state management
/// - Real-time waveform data and duration tracking  
/// - Authentication flow integration
/// - Upload progress and error handling
/// - Permission management and user feedback
@MainActor
final class CallViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var meterLevel: Double = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var hasPermissions = false
    @Published var lastRecording: LocalRecording?
    @Published var uploadState: UploadState = .idle
    @Published var isAuthenticated = false
    @Published var showSignIn = false
    
    private let audioService: AudioServiceProtocol
    private let uploadService: AudioUploadServiceProtocol
    private let authService: AuthServiceProtocol
    private let capsuleService: CapsuleServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    init(
        audioService: AudioServiceProtocol = AudioService(),
        uploadService: AudioUploadServiceProtocol = AudioUploadService(),
        authService: AuthServiceProtocol,
        capsuleService: CapsuleServiceProtocol = CapsuleService()
    ) {
        self.audioService = audioService
        self.uploadService = uploadService
        self.authService = authService
        self.capsuleService = capsuleService
        setupBindings()
        checkPermissions()
        setupAuthBindings()
    }
    
    deinit {
        recordingTimer?.invalidate()
    }
    
    private func setupBindings() {
        audioService.meterLevelPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.meterLevel, on: self)
            .store(in: &cancellables)
    }
    
    private func setupAuthBindings() {
        authService.authStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                switch authState {
                case .authenticated:
                    self?.isAuthenticated = true
                    self?.showSignIn = false
                case .unauthenticated:
                    self?.isAuthenticated = false
                case .loading:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkPermissions() {
        Task {
            hasPermissions = await audioService.requestPermissions()
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard hasPermissions else {
            showPermissionError()
            return
        }
        
        Task {
            do {
                try await audioService.startRecording()
                isRecording = true
                recordingStartTime = Date()
                startRecordingTimer()
                clearError()
            } catch {
                handleError(error)
            }
        }
    }
    
    private func stopRecording() {
        Task {
            do {
                let recording = try await audioService.stopRecording()
                isRecording = false
                stopRecordingTimer()
                recordingDuration = 0
                lastRecording = recording
                clearError()
                
                // Start upload process if authenticated
                if isAuthenticated {
                    await uploadRecording(recording)
                } else {
                    showSignIn = true
                }
            } catch {
                handleError(error)
                isRecording = false
                stopRecordingTimer()
                recordingDuration = 0
            }
        }
    }
    
    func cancelRecording() {
        audioService.cancelRecording()
        isRecording = false
        stopRecordingTimer()
        recordingDuration = 0
        meterLevel = 0.0
        clearError()
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }
    
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
    
    private func showPermissionError() {
        errorMessage = "Microphone permission is required to record voice capsules."
        showError = true
    }
    
    private func clearError() {
        errorMessage = nil
        showError = false
    }
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var canRecord: Bool {
        hasPermissions && !isRecording
    }
    
    var canStop: Bool {
        isRecording
    }
    
    var isUploading: Bool {
        if case .uploading = uploadState {
            return true
        }
        return false
    }
    
    var uploadProgress: Double {
        if case .uploading(let progress) = uploadState {
            return progress
        }
        return 0.0
    }
    
    // MARK: - Authentication Methods
    
    func signInWithApple() {
        Task {
            do {
                let _ = try await authService.signInWithApple()
                
                // Upload any pending recording after successful auth
                if let recording = lastRecording {
                    await uploadRecording(recording)
                }
            } catch {
                handleError(error)
            }
        }
    }
    
    func dismissSignIn() {
        showSignIn = false
    }
    
    // MARK: - Upload Methods
    
    private func uploadRecording(_ recording: LocalRecording) async {
        guard isAuthenticated else {
            showSignIn = true
            return
        }
        
        uploadState = .uploading(progress: 0.0)
        
        do {
            let capsule = try await uploadService.uploadAudio(recording: recording) { [weak self] progress in
                Task { @MainActor in
                    self?.uploadState = .uploading(progress: progress)
                }
            }
            
            uploadState = .completed(capsule)
            HapticFeedback.notification(.success)
            
            // Save capsule to local database with local file URL
            try await capsuleService.saveCapsule(capsule, localFileURL: recording.url)
            
            // Clean up local file after successful upload and save
            try? FileManager.default.removeItem(at: recording.url)
            
        } catch {
            uploadState = .failed(error)
            HapticFeedback.notification(.error)
            handleError(error)
        }
    }
    
    func retryUpload() {
        guard let recording = lastRecording else { return }
        
        Task {
            await uploadRecording(recording)
        }
    }
    
    func cancelUpload() {
        guard let recording = lastRecording else { return }
        
        uploadService.cancelUpload(for: recording.id)
        uploadState = .idle
    }
    
    func dismissUploadResult() {
        uploadState = .idle
        lastRecording = nil
    }
    
    // MARK: - Computed Properties for UI
    
    var uploadCompleted: Bool {
        if case .completed = uploadState {
            return true
        }
        return false
    }
    
    var uploadFailed: Bool {
        if case .failed = uploadState {
            return true
        }
        return false
    }
    
    var uploadErrorMessage: String? {
        if case .failed(let error) = uploadState {
            return error.localizedDescription
        }
        return nil
    }
}