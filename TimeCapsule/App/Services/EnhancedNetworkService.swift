import Foundation
import Network
import Combine

/// Enhanced NetworkService with retry logic, security improvements, and offline support
final class EnhancedNetworkService: NetworkServiceProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let retryConfiguration: RetryConfiguration
    private let circuitBreaker: CircuitBreaker
    private let requestCache: NetworkCache
    private let reachability: NetworkReachability
    private let offlineQueue: OfflineRequestQueue
    
    // Request deduplication
    private var activeRequests: [String: Task<Any, Error>] = [:]
    private let requestLock = NSLock()
    
    init() {
        guard let url = URL(string: Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String ?? "https://api.timecapsule.live") else {
            fatalError("Invalid backend URL")
        }
        self.baseURL = url
        
        // Enhanced URLSession configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        
        self.session = URLSession(
            configuration: config,
            delegate: CertificatePinningDelegate(),
            delegateQueue: nil
        )
        
        self.retryConfiguration = RetryConfiguration.default
        self.circuitBreaker = CircuitBreaker()
        self.requestCache = NetworkCache()
        self.reachability = NetworkReachability()
        self.offlineQueue = OfflineRequestQueue()
        
        setupNetworkMonitoring()
    }
    
    // MARK: - NetworkServiceProtocol Implementation with Enhancements
    
    func get<T: Codable>(path: String) async throws -> T {
        return try await executeRequest(
            method: .GET,
            path: path,
            body: nil,
            responseType: T.self
        )
    }
    
    func post<T: Codable>(path: String, body: [String: Any]) async throws -> T {
        return try await executeRequest(
            method: .POST,
            path: path,
            body: body,
            responseType: T.self
        )
    }
    
    func upload<T: Codable>(path: String, fileURL: URL, parameters: [String: Any]) async throws -> T {
        return try await executeUploadRequest(
            path: path,
            fileURL: fileURL,
            parameters: parameters,
            responseType: T.self
        )
    }
    
    // MARK: - Enhanced Request Execution
    
    private func executeRequest<T: Codable>(
        method: HTTPMethod,
        path: String,
        body: [String: Any]?,
        responseType: T.Type
    ) async throws -> T {
        let request = try await buildRequest(method: method, path: path, body: body)
        let requestKey = request.cacheKey
        
        // Check for duplicate requests
        return try await withDeduplication(key: requestKey) {
            // Check cache first for GET requests
            if method == .GET,
               let cached: T = await requestCache.getCachedResponse(for: request) {
                return cached
            }
            
            // Check network connectivity
            guard reachability.isConnected else {
                if method == .GET {
                    // Try cache for offline GET requests
                    if let cached: T = await requestCache.getCachedResponse(for: request, ignoreExpiry: true) {
                        return cached
                    }
                }
                
                // Queue request for later if offline
                await offlineQueue.enqueue(request)
                throw NetworkError.networkUnavailable
            }
            
            // Execute with circuit breaker and retry logic
            return try await circuitBreaker.execute {
                try await retryWithBackoff { attempt in
                    try await performRequest(request: request, responseType: responseType)
                }
            }
        }
    }
    
    private func executeUploadRequest<T: Codable>(
        path: String,
        fileURL: URL,
        parameters: [String: Any],
        responseType: T.Type
    ) async throws -> T {
        let request = try await buildUploadRequest(path: path, fileURL: fileURL, parameters: parameters)
        
        return try await circuitBreaker.execute {
            try await retryWithBackoff(maxAttempts: 2) { attempt in
                try await performUploadRequest(request: request, fileURL: fileURL, responseType: responseType)
            }
        }
    }
    
    // MARK: - Request Building with Security
    
    private func buildRequest(
        method: HTTPMethod,
        path: String,
        body: [String: Any]?
    ) async throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        // Add security headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("iOS", forHTTPHeaderField: "X-Platform")
        request.setValue(Bundle.main.appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        
        // Add authentication if not auth endpoint
        if !path.contains("/auth/") {
            try await addAuthHeaders(to: &request)
        }
        
        // Add body for POST requests
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        return request
    }
    
    private func buildUploadRequest(
        path: String,
        fileURL: URL,
        parameters: [String: Any]
    ) async throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        try await addAuthHeaders(to: &request)
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        return request
    }
    
    private func addAuthHeaders(to request: inout URLRequest) async throws {
        let keychain = KeychainHelper()
        
        if let tokenData = keychain.load(key: "auth_token"),
           let token = try? JSONDecoder().decode(AuthToken.self, from: tokenData),
           !token.isExpired {
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            throw NetworkError.unauthorized
        }
    }
    
    // MARK: - Request Execution with Validation
    
    private func performRequest<T: Codable>(
        request: URLRequest,
        responseType: T.Type
    ) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        let result: T = try JSONDecoder.api.decode(T.self, from: data)
        
        // Cache successful GET responses
        if request.httpMethod == "GET" {
            await requestCache.cache(result, for: request)
        }
        
        return result
    }
    
    private func performUploadRequest<T: Codable>(
        request: URLRequest,
        fileURL: URL,
        responseType: T.Type
    ) async throws -> T {
        let boundary = extractBoundary(from: request)
        let body = try createMultipartBody(boundary: boundary, fileURL: fileURL, parameters: [:])
        
        var uploadRequest = request
        uploadRequest.httpBody = body
        
        let (data, response) = try await session.data(for: uploadRequest)
        try validateResponse(response)
        
        return try JSONDecoder.api.decode(T.self, from: data)
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw NetworkError.unauthorized
        case 403:
            throw NetworkError.forbidden
        case 404:
            throw NetworkError.notFound
        case 429:
            throw NetworkError.rateLimited
        case 400...499:
            throw NetworkError.clientError(httpResponse.statusCode)
        case 500...599:
            throw NetworkError.serverError(httpResponse.statusCode)
        default:
            throw NetworkError.unknown
        }
    }
    
    // MARK: - Retry Logic with Exponential Backoff
    
    private func retryWithBackoff<T>(
        maxAttempts: Int = 3,
        operation: @escaping (Int) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation(attempt)
            } catch {
                lastError = error
                
                guard attempt < maxAttempts,
                      shouldRetry(error) else {
                    throw error
                }
                
                let delay = calculateDelay(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? NetworkError.unknown
    }
    
    private func shouldRetry(_ error: Error) -> Bool {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .serverError(let code) where code >= 500:
                return true
            case .rateLimited:
                return true
            case .networkUnavailable:
                return false // Don't retry if offline
            default:
                return false
            }
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost:
                return true
            default:
                return false
            }
        }
        
        return false
    }
    
    private func calculateDelay(attempt: Int) -> TimeInterval {
        let baseDelay = retryConfiguration.baseDelay
        let exponentialDelay = baseDelay * pow(retryConfiguration.backoffMultiplier, Double(attempt - 1))
        let jitterRange = exponentialDelay * retryConfiguration.jitter
        let jitter = Double.random(in: -jitterRange...jitterRange)
        return min(exponentialDelay + jitter, retryConfiguration.maxDelay)
    }
    
    // MARK: - Request Deduplication
    
    private func withDeduplication<T>(key: String, operation: @escaping () async throws -> T) async throws -> T {
        requestLock.lock()
        defer { requestLock.unlock() }
        
        if let existingTask = activeRequests[key] {
            return try await existingTask.value as! T
        }
        
        let task = Task {
            defer {
                requestLock.lock()
                activeRequests.removeValue(forKey: key)
                requestLock.unlock()
            }
            return try await operation()
        }
        
        activeRequests[key] = task
        return try await task.value
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        reachability.startMonitoring()
        
        // Process offline queue when connection is restored
        reachability.$isConnected
            .filter { $0 }
            .sink { [weak self] _ in
                Task {
                    await self?.offlineQueue.processQueue()
                }
            }
            .store(in: &reachability.cancellables)
    }
    
    // MARK: - Helper Methods
    
    private func extractBoundary(from request: URLRequest) -> String {
        guard let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              let boundaryRange = contentType.range(of: "boundary=") else {
            return UUID().uuidString
        }
        return String(contentType[boundaryRange.upperBound...])
    }
    
    private func createMultipartBody(boundary: String, fileURL: URL, parameters: [String: Any]) throws -> Data {
        var body = Data()
        
        // Add parameters
        for (key, value) in parameters {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Add file
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = "audio/wav"
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}

// MARK: - Supporting Types

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

struct RetryConfiguration {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let backoffMultiplier: Double
    let jitter: Double
    let maxDelay: TimeInterval
    
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        baseDelay: 1.0,
        backoffMultiplier: 2.0,
        jitter: 0.1,
        maxDelay: 30.0
    )
}

// MARK: - Circuit Breaker Pattern

final class CircuitBreaker {
    private enum State {
        case closed
        case open
        case halfOpen
    }
    
    private var state: State = .closed
    private var failureCount = 0
    private var lastFailureTime: Date?
    private let failureThreshold = 5
    private let recoveryTimeout: TimeInterval = 30
    private let lock = NSLock()
    
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        lock.lock()
        let currentState = state
        lock.unlock()
        
        switch currentState {
        case .open:
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) > recoveryTimeout {
                lock.lock()
                state = .halfOpen
                lock.unlock()
            } else {
                throw NetworkError.circuitBreakerOpen
            }
        case .halfOpen, .closed:
            break
        }
        
        do {
            let result = try await operation()
            recordSuccess()
            return result
        } catch {
            recordFailure()
            throw error
        }
    }
    
    private func recordSuccess() {
        lock.lock()
        defer { lock.unlock() }
        
        failureCount = 0
        state = .closed
        lastFailureTime = nil
    }
    
    private func recordFailure() {
        lock.lock()
        defer { lock.unlock() }
        
        failureCount += 1
        lastFailureTime = Date()
        
        if failureCount >= failureThreshold {
            state = .open
        }
    }
}

// MARK: - Network Cache

final class NetworkCache {
    private let cache = NSCache<NSString, CachedResponse>()
    private let cacheQueue = DispatchQueue(label: "network.cache", attributes: .concurrent)
    
    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    func getCachedResponse<T: Codable>(
        for request: URLRequest,
        ignoreExpiry: Bool = false
    ) async -> T? {
        return await withCheckedContinuation { continuation in
            cacheQueue.async {
                let key = request.cacheKey as NSString
                
                guard let cached = self.cache.object(forKey: key) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                if !ignoreExpiry && cached.isExpired {
                    self.cache.removeObject(forKey: key)
                    continuation.resume(returning: nil)
                    return
                }
                
                do {
                    let result = try JSONDecoder.api.decode(T.self, from: cached.data)
                    continuation.resume(returning: result)
                } catch {
                    self.cache.removeObject(forKey: key)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    func cache<T: Codable>(_ object: T, for request: URLRequest) async {
        guard let data = try? JSONEncoder().encode(object) else { return }
        
        await withCheckedContinuation { continuation in
            cacheQueue.async(flags: .barrier) {
                let key = request.cacheKey as NSString
                let cached = CachedResponse(data: data, timestamp: Date())
                self.cache.setObject(cached, forKey: key)
                continuation.resume()
            }
        }
    }
}

final class CachedResponse {
    let data: Data
    let timestamp: Date
    
    init(data: Data, timestamp: Date) {
        self.data = data
        self.timestamp = timestamp
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 300 // 5 minutes
    }
}

// MARK: - Network Reachability

final class NetworkReachability: ObservableObject {
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType = .other
    
    fileprivate var cancellables = Set<AnyCancellable>()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type ?? .other
            }
        }
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
}

// MARK: - Offline Request Queue

final class OfflineRequestQueue {
    private var queuedRequests: [QueuedRequest] = []
    private let queue = DispatchQueue(label: "offline.queue", attributes: .concurrent)
    
    func enqueue(_ request: URLRequest) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let queuedRequest = QueuedRequest(request: request, timestamp: Date())
                self.queuedRequests.append(queuedRequest)
                continuation.resume()
            }
        }
    }
    
    func processQueue() async {
        // Implementation would retry queued requests
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                // Process queued requests
                self.queuedRequests.removeAll()
                continuation.resume()
            }
        }
    }
}

struct QueuedRequest {
    let request: URLRequest
    let timestamp: Date
    var retryCount = 0
}

// MARK: - Enhanced Network Errors

enum NetworkError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case clientError(Int)
    case serverError(Int)
    case networkUnavailable
    case circuitBreakerOpen
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response received"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .clientError(let code):
            return "Client error: \(code)"
        case .serverError(let code):
            return "Server error: \(code)"
        case .networkUnavailable:
            return "Network unavailable. Check your connection."
        case .circuitBreakerOpen:
            return "Service temporarily unavailable"
        case .unknown:
            return "Unknown network error"
        }
    }
}

// MARK: - Certificate Pinning

class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    private let pinnedCertificates = [
        "api.timecapsule.live": "SHA256_HASH_OF_CERTIFICATE"
    ]
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // In production, implement proper certificate pinning
        // For now, use default validation
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - Extensions

extension URLRequest {
    var cacheKey: String {
        let method = httpMethod ?? "GET"
        let urlString = url?.absoluteString ?? ""
        return "\(method):\(urlString)"
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}