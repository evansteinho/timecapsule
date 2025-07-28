import Foundation
import Combine

protocol AudioUploadServiceProtocol {
    func uploadAudio(recording: LocalRecording, progress: @escaping (Double) -> Void) async throws -> Capsule
    func cancelUpload(for recordingId: UUID)
}

final class AudioUploadService: AudioUploadServiceProtocol {
    private let networkService: NetworkServiceProtocol
    private var uploadTasks: [UUID: URLSessionUploadTask] = [:]
    private let session: URLSession
    
    init(networkService: NetworkServiceProtocol = NetworkService()) {
        self.networkService = networkService
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    func uploadAudio(recording: LocalRecording, progress: @escaping (Double) -> Void) async throws -> Capsule {
        // Step 1: Create capsule record on backend
        let uploadResponse = try await createCapsuleRecord(recording: recording)
        
        // Step 2: Upload audio file
        if let uploadURL = uploadResponse.uploadURL {
            try await uploadAudioFile(
                recordingId: recording.id,
                fileURL: recording.url,
                uploadURL: uploadURL,
                progress: progress
            )
        } else {
            // Direct upload to our backend
            try await uploadAudioDirect(
                recordingId: recording.id,
                fileURL: recording.url,
                capsuleId: uploadResponse.capsule.id,
                progress: progress
            )
        }
        
        // Step 3: Mark upload as complete
        let completedCapsule = try await markUploadComplete(capsuleId: uploadResponse.capsule.id)
        
        return completedCapsule
    }
    
    func cancelUpload(for recordingId: UUID) {
        uploadTasks[recordingId]?.cancel()
        uploadTasks.removeValue(forKey: recordingId)
    }
    
    private func createCapsuleRecord(recording: LocalRecording) async throws -> CapsuleUploadResponse {
        let parameters: [String: Any] = [
            "duration": recording.duration,
            "file_size": recording.fileSize,
            "created_at": ISO8601DateFormatter().string(from: recording.createdAt)
        ]
        
        let response: CapsuleUploadResponse = try await networkService.post(
            path: "/v0/capsules",
            body: parameters
        )
        
        return response
    }
    
    private func uploadAudioFile(
        recordingId: UUID,
        fileURL: URL,
        uploadURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"
            request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
            
            let uploadTask = session.uploadTask(with: request, fromFile: fileURL) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      200...299 ~= httpResponse.statusCode else {
                    continuation.resume(throwing: AudioUploadError.uploadFailed)
                    return
                }
                
                continuation.resume()
            }
            
            // Track progress using URLSessionTaskDelegate
            let delegate = UploadProgressDelegate { [weak self] progressValue in
                Task { @MainActor [weak self] in
                    progress(progressValue)
                }
            }
            
            // Store the task for potential cancellation
            uploadTasks[recordingId] = uploadTask
            
            uploadTask.resume()
        }
    }
    
    private func uploadAudioDirect(
        recordingId: UUID,
        fileURL: URL,
        capsuleId: String,
        progress: @escaping (Double) -> Void
    ) async throws {
        let parameters: [String: Any] = [
            "capsule_id": capsuleId
        ]
        
        // Simulate progress for direct upload
        Task {
            for i in 1...10 {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await MainActor.run {
                    progress(Double(i) / 10.0)
                }
            }
        }
        
        let _: CapsuleUploadResponse = try await networkService.upload(
            path: "/v0/capsules/\(capsuleId)/audio",
            fileURL: fileURL,
            parameters: parameters
        )
    }
    
    private func markUploadComplete(capsuleId: String) async throws -> Capsule {
        let parameters: [String: Any] = [
            "status": "processing"
        ]
        
        let response: Capsule = try await networkService.post(
            path: "/v0/capsules/\(capsuleId)/complete",
            body: parameters
        )
        
        return response
    }
}

// MARK: - Upload Progress Delegate
private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let progressHandler: (Double) -> Void
    
    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        progressHandler(progress)
    }
}

// MARK: - Upload Errors
enum AudioUploadError: LocalizedError {
    case fileNotFound
    case uploadFailed
    case networkError
    case serverError
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .uploadFailed:
            return "Failed to upload audio file"
        case .networkError:
            return "Network error during upload"
        case .serverError:
            return "Server error during upload"
        case .cancelled:
            return "Upload was cancelled"
        }
    }
}