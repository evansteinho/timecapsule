# TimeCapsule API Documentation

## Overview

This document provides comprehensive API documentation for the TimeCapsule iOS app's internal services and external API endpoints. 

**Current Status**: 21 Swift files, 2,542 lines of code across Phases 1-3 implementation.

## Table of Contents

- [Services](#services)
- [Models](#models)  
- [UI Components](#ui-components)
- [API Endpoints](#api-endpoints)
- [Error Handling](#error-handling)
- [Authentication](#authentication)

## Services

### AudioService

The `AudioService` handles all audio recording functionality.

```swift
protocol AudioServiceProtocol {
    var isRecording: Bool { get }
    var meterLevel: Double { get }
    var meterLevelPublisher: AnyPublisher<Double, Never> { get }
    
    func requestPermissions() async -> Bool
    func startRecording() async throws
    func stopRecording() async throws -> LocalRecording
    func cancelRecording()
}
```

**Key Features:**
- Records 16 kHz mono WAV files
- Real-time audio level metering
- Automatic file management in Application Support directory
- Reactive updates via Combine publishers

**File Naming Convention:**
```
YYYYMMDD_HHMMSS.wav
```

### AuthService

Manages user authentication using Sign in with Apple.

```swift
protocol AuthServiceProtocol {
    var isAuthenticated: Bool { get }
    var currentUser: User? { get }
    var authStatePublisher: AnyPublisher<AuthState, Never> { get }
    
    func signInWithApple() async throws -> AuthResponse
    func refreshToken() async throws -> AuthToken
    func signOut()
    func getValidToken() async throws -> String
}
```

**Authentication Flow:**
1. User initiates Sign in with Apple
2. App receives Apple ID credential
3. Credential sent to backend for validation
4. Backend returns JWT tokens
5. Tokens stored securely in Keychain

### NetworkService

Generic HTTP client for API communication.

```swift
protocol NetworkServiceProtocol {
    func get<T: Codable>(path: String) async throws -> T
    func post<T: Codable>(path: String, body: [String: Any]) async throws -> T
    func upload<T: Codable>(path: String, fileURL: URL, parameters: [String: Any]) async throws -> T
}
```

**Features:**
- Automatic authentication header injection
- Error handling and status code validation
- Multi-part file upload support
- Configurable timeouts

### AudioUploadService

Handles uploading recorded audio files to the cloud.

```swift
protocol AudioUploadServiceProtocol {
    func uploadAudio(recording: LocalRecording, progress: @escaping (Double) -> Void) async throws -> Capsule
    func cancelUpload(for recordingId: UUID)
}
```

**Upload Process:**
1. Create capsule record on backend
2. Upload audio file (direct or signed URL)
3. Mark upload as complete
4. Return completed `Capsule` object

## Models

### User

Represents an authenticated user.

```swift
struct User: Codable, Identifiable {
    let id: String
    let email: String?
    let name: String?
    let createdAt: Date
    let isProUser: Bool
}
```

### AuthToken

JWT authentication token with refresh capability.

```swift
struct AuthToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    
    var isExpired: Bool { /* 5 minute buffer */ }
}
```

### LocalRecording

Represents a local audio recording file.

```swift
struct LocalRecording: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let duration: TimeInterval
    let fileSize: Int64
    let createdAt: Date
    
    // Computed properties
    var filename: String
    var formattedDuration: String
    var formattedFileSize: String
    var exists: Bool
}
```

### Capsule

Server-side representation of an uploaded recording.

```swift
struct Capsule: Identifiable, Codable {
    let id: String
    let userId: String
    let audioURL: URL?
    let transcription: String?
    let duration: TimeInterval
    let fileSize: Int64
    let createdAt: Date
    let updatedAt: Date
    let status: CapsuleStatus
    let metadata: CapsuleMetadata?
}
```

**CapsuleStatus Values:**
- `uploading`: File being uploaded
- `processing`: Audio being processed
- `transcribing`: Generating transcription
- `completed`: Ready for use
- `failed`: Processing failed

## API Endpoints

### Authentication

#### POST /auth/apple
Sign in with Apple ID credential.

**Request:**
```json
{
  "identity_token": "string",
  "user_identifier": "string", 
  "email": "string",
  "full_name": {
    "given_name": "string",
    "family_name": "string"
  }
}
```

**Response:**
```json
{
  "user": {
    "id": "string",
    "email": "string",
    "name": "string",
    "created_at": "2025-01-27T12:00:00.000000Z",
    "is_pro_user": false
  },
  "token": {
    "access_token": "string",
    "refresh_token": "string", 
    "expires_at": "2025-01-27T13:00:00.000000Z"
  }
}
```

#### POST /auth/refresh
Refresh an expired access token.

**Request:**
```json
{
  "refresh_token": "string"
}
```

**Response:**
```json
{
  "access_token": "string",
  "refresh_token": "string",
  "expires_at": "2025-01-27T13:00:00.000000Z"
}
```

### User Management

#### GET /user/me
Get current user information.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:**
```json
{
  "id": "string",
  "email": "string", 
  "name": "string",
  "created_at": "2025-01-27T12:00:00.000000Z",
  "is_pro_user": false
}
```

### Capsules

#### POST /v0/capsules
Create a new capsule record.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Request:**
```json
{
  "duration": 30.5,
  "file_size": 122880,
  "created_at": "2025-01-27T12:00:00.000000Z"
}
```

**Response:**
```json
{
  "capsule": {
    "id": "string",
    "user_id": "string",
    "audio_url": null,
    "transcription": null,
    "duration": 30.5,
    "file_size": 122880,
    "created_at": "2025-01-27T12:00:00.000000Z",
    "updated_at": "2025-01-27T12:00:00.000000Z",
    "status": "uploading",
    "metadata": null
  },
  "upload_url": "https://signed-upload-url.com"
}
```

#### POST /v0/capsules/{id}/audio
Upload audio file directly to backend.

**Headers:**
```
Authorization: Bearer <access_token>
Content-Type: multipart/form-data
```

**Request:**
```
Content-Disposition: form-data; name="capsule_id"
<capsule_id>

Content-Disposition: form-data; name="audio"; filename="recording.wav"
Content-Type: audio/wav
<binary_audio_data>
```

#### POST /v0/capsules/{id}/complete
Mark upload as complete and begin processing.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Request:**
```json
{
  "status": "processing"
}
```

**Response:**
```json
{
  "id": "string",
  "user_id": "string", 
  "audio_url": "https://storage.com/audio.wav",
  "transcription": null,
  "duration": 30.5,
  "file_size": 122880,
  "created_at": "2025-01-27T12:00:00.000000Z",
  "updated_at": "2025-01-27T12:00:00.000000Z",
  "status": "processing",
  "metadata": null
}
```

## Error Handling

### Network Errors

```swift
enum NetworkError: LocalizedError {
    case invalidResponse
    case unauthorized       // 401
    case forbidden         // 403  
    case notFound         // 404
    case clientError(Int) // 400-499
    case serverError(Int) // 500-599
    case unknown
}
```

### Audio Errors

```swift
enum AudioServiceError: LocalizedError {
    case permissionDenied
    case recordingFailed
    case notRecording
    case recordingNotFound
}
```

### Upload Errors

```swift
enum AudioUploadError: LocalizedError {
    case fileNotFound
    case uploadFailed
    case networkError
    case serverError
    case cancelled
}
```

## Authentication

### Token Management

- **Access Token**: Short-lived (1 hour), used for API requests
- **Refresh Token**: Long-lived (30 days), used to get new access tokens
- **Automatic Refresh**: Tokens refreshed 5 minutes before expiration
- **Secure Storage**: All tokens stored in iOS Keychain

### Security Headers

All authenticated requests include:
```
Authorization: Bearer <access_token>
Content-Type: application/json
```

### Error Handling

When a request returns 401 Unauthorized:
1. Attempt token refresh using refresh token
2. If refresh succeeds, retry original request
3. If refresh fails, redirect user to sign in

## Configuration

### Environment Variables

Set in `Config/Debug.xcconfig` and `Config/Release.xcconfig`:

```bash
WHISPER_API_KEY = $(WHISPER_API_KEY)
OPENAI_API_KEY = $(OPENAI_API_KEY) 
ELEVENLABS_API_KEY = $(ELEVENLABS_API_KEY)
PINECONE_API_KEY = $(PINECONE_API_KEY)
BACKEND_BASE_URL = https://api.timecapsule.live
```

### Keychain Storage

**Service**: `com.timecapsule.app`
**Account**: `auth_token`
**Access**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

## UI Components

### RecordingButton
Reusable recording button component with animations and accessibility.

```swift
struct RecordingButton: View {
    let isRecording: Bool
    let hasPermissions: Bool
    let action: () -> Void
}
```

**Features:**
- Adaptive sizing with Dynamic Type support
- Pulse animation when recording
- Accessibility labels and hints
- Haptic feedback integration

### UploadProgressView
Progress overlay for audio upload operations.

```swift
struct UploadProgressView: View {
    let progress: Double
}
```

**Features:**
- Material background with blur effect
- Animated progress bar with gradients
- Real-time progress percentage display

### SignInView
Sign in with Apple interface with benefits showcase.

```swift
struct SignInView: View {
    @ObservedObject var viewModel: CallViewModel
}
```

**Features:**
- Native Sign in with Apple button
- App benefits presentation
- Material design with proper spacing

## Testing

### Mock Services

For testing, use mock implementations:

```swift
class MockAudioService: AudioServiceProtocol {
    var shouldGrantPermissions = true
    var shouldFailRecording = false
    // ... implementation
}
```

### Unit Test Coverage

- ✅ AudioService recording functionality
- ✅ Authentication token management  
- ✅ Network service error handling
- ✅ UI component accessibility
- 🚧 Upload service (planned)
- 🚧 UI ViewModels (planned)

## Code Metrics

- **Total Files**: 21 Swift files
- **Lines of Code**: 2,542 (excluding comments/whitespace)
- **Test Coverage**: Core services fully tested
- **Documentation**: Comprehensive inline and external docs

---

*This documentation is automatically updated when code changes are made.*