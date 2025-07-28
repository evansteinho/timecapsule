import Foundation

protocol NetworkServiceProtocol {
    func get<T: Codable>(path: String) async throws -> T
    func post<T: Codable>(path: String, body: [String: Any]) async throws -> T
    func upload<T: Codable>(path: String, fileURL: URL, parameters: [String: Any]) async throws -> T
    func setAuthToken(_ token: String?)
}

final class NetworkService: NetworkServiceProtocol {
    private let baseURL: URL
    private let session: URLSession
    private var authToken: String?
    
    init() {
        guard let url = URL(string: Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String ?? "https://api.timecapsule.live") else {
            fatalError("Invalid backend URL")
        }
        self.baseURL = url
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }
    
    func get<T: Codable>(path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        try await addAuthHeaders(to: &request)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder.api.decode(T.self, from: data)
    }
    
    func post<T: Codable>(path: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if !path.contains("/auth/") {
            try await addAuthHeaders(to: &request)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder.api.decode(T.self, from: data)
    }
    
    func upload<T: Codable>(path: String, fileURL: URL, parameters: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        try await addAuthHeaders(to: &request)
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let body = try createMultipartBody(boundary: boundary, fileURL: fileURL, parameters: parameters)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder.api.decode(T.self, from: data)
    }
    
    private func addAuthHeaders(to request: inout URLRequest) async throws {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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
        case 400...499:
            throw NetworkError.clientError(httpResponse.statusCode)
        case 500...599:
            throw NetworkError.serverError(httpResponse.statusCode)
        default:
            throw NetworkError.unknown
        }
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

enum NetworkError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case clientError(Int)
    case serverError(Int)
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
        case .clientError(let code):
            return "Client error: \(code)"
        case .serverError(let code):
            return "Server error: \(code)"
        case .unknown:
            return "Unknown network error"
        }
    }
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        decoder.dateDecodingStrategy = .formatted(formatter)
        return decoder
    }()
}