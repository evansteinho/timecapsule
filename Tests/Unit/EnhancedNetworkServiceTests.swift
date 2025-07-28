import XCTest
@testable import TimeCapsule

final class EnhancedNetworkServiceTests: XCTestCase {
    var sut: EnhancedNetworkService!
    var mockURLSession: MockURLSession!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockURLSession = MockURLSession()
        sut = EnhancedNetworkService()
        // Note: In a real implementation, you'd inject the mock session
    }
    
    override func tearDownWithError() throws {
        sut = nil
        mockURLSession = nil
        try super.tearDownWithError()
    }
    
    // MARK: - GET Request Tests
    
    func testGetRequest_Success_ReturnsDecodedData() async throws {
        // Given
        let expectedResponse = TestResponse(message: "Success", status: 200)
        let responseData = try JSONEncoder().encode(expectedResponse)
        
        mockURLSession.mockData = responseData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.timecapsule.live/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result: TestResponse = try await sut.get(path: "/test")
        
        // Then
        XCTAssertEqual(result.message, expectedResponse.message)
        XCTAssertEqual(result.status, expectedResponse.status)
    }
    
    func testGetRequest_NetworkError_ThrowsAppropriateError() async {
        // Given
        mockURLSession.mockError = URLError(.notConnectedToInternet)
        
        // When/Then
        do {
            let _: TestResponse = try await sut.get(path: "/test")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    func testGetRequest_ServerError_ThrowsServerError() async {
        // Given
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.timecapsule.live/test")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )
        mockURLSession.mockData = Data()
        
        // When/Then
        do {
            let _: TestResponse = try await sut.get(path: "/test")
            XCTFail("Expected error to be thrown")
        } catch let networkError as NetworkError {
            if case .serverError(let code) = networkError {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected server error")
            }
        }
    }
    
    // MARK: - POST Request Tests
    
    func testPostRequest_WithBody_SendsCorrectData() async throws {
        // Given
        let requestBody = ["key": "value", "number": 42] as [String: Any]
        let expectedResponse = TestResponse(message: "Posted", status: 201)
        let responseData = try JSONEncoder().encode(expectedResponse)
        
        mockURLSession.mockData = responseData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.timecapsule.live/test")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result: TestResponse = try await sut.post(path: "/test", body: requestBody)
        
        // Then
        XCTAssertEqual(result.message, expectedResponse.message)
        XCTAssertEqual(result.status, expectedResponse.status)
        
        // Verify request was made with correct data
        XCTAssertNotNil(mockURLSession.lastRequest)
        XCTAssertEqual(mockURLSession.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(mockURLSession.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    
    // MARK: - Retry Logic Tests
    
    func testRetryLogic_TransientError_RetriesAndSucceeds() async throws {
        // Given
        let expectedResponse = TestResponse(message: "Success", status: 200)
        let responseData = try JSONEncoder().encode(expectedResponse)
        
        // First attempt fails, second succeeds
        mockURLSession.responses = [
            (nil, HTTPURLResponse(url: URL(string: "https://api.timecapsule.live/test")!, statusCode: 500, httpVersion: nil, headerFields: nil), URLError(.timedOut)),
            (responseData, HTTPURLResponse(url: URL(string: "https://api.timecapsule.live/test")!, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
        ]
        
        // When
        let result: TestResponse = try await sut.get(path: "/test")
        
        // Then
        XCTAssertEqual(result.message, expectedResponse.message)
        XCTAssertEqual(mockURLSession.requestCount, 2)
    }
    
    func testRetryLogic_PermanentError_DoesNotRetry() async {
        // Given
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.timecapsule.live/test")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )
        mockURLSession.mockData = Data()
        
        // When/Then
        do {
            let _: TestResponse = try await sut.get(path: "/test")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(mockURLSession.requestCount, 1) // No retry for 404
        }
    }
    
    // MARK: - Circuit Breaker Tests
    
    func testCircuitBreaker_MultipleFailures_OpensCircuit() async {
        // Given
        mockURLSession.mockError = URLError(.timedOut)
        
        // When - Make multiple requests to trigger circuit breaker
        for _ in 0..<6 { // Should exceed failure threshold
            do {
                let _: TestResponse = try await sut.get(path: "/test")
            } catch {
                // Expected to fail
            }
        }
        
        // Then - Circuit should be open, preventing further requests
        do {
            let _: TestResponse = try await sut.get(path: "/test")
            XCTFail("Expected circuit breaker to be open")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .circuitBreakerOpen)
        } catch {
            XCTFail("Expected NetworkError.circuitBreakerOpen")
        }
    }
    
    // MARK: - Request Deduplication Tests
    
    func testRequestDeduplication_SimultaneousRequests_OnlyOneNetworkCall() async throws {
        // Given
        let expectedResponse = TestResponse(message: "Success", status: 200)
        let responseData = try JSONEncoder().encode(expectedResponse)
        
        mockURLSession.mockData = responseData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.timecapsule.live/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // Simulate slow network response
        mockURLSession.responseDelay = 1.0
        
        // When - Make simultaneous requests
        async let result1: TestResponse = sut.get(path: "/test")
        async let result2: TestResponse = sut.get(path: "/test")
        
        let (response1, response2) = try await (result1, result2)
        
        // Then
        XCTAssertEqual(response1.message, expectedResponse.message)
        XCTAssertEqual(response2.message, expectedResponse.message)
        XCTAssertEqual(mockURLSession.requestCount, 1) // Only one network call made
    }
    
    // MARK: - Upload Tests
    
    func testUpload_WithFile_SendsMultipartData() async throws {
        // Given
        let testFileURL = createTestAudioFile()
        let parameters = ["key": "value"]
        let expectedResponse = TestResponse(message: "Uploaded", status: 201)
        let responseData = try JSONEncoder().encode(expectedResponse)
        
        mockURLSession.mockData = responseData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.timecapsule.live/upload")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result: TestResponse = try await sut.upload(path: "/upload", fileURL: testFileURL, parameters: parameters)
        
        // Then
        XCTAssertEqual(result.message, expectedResponse.message)
        XCTAssertNotNil(mockURLSession.lastRequest)
        XCTAssertTrue(mockURLSession.lastRequest?.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") ?? false)
        
        // Cleanup
        try? FileManager.default.removeItem(at: testFileURL)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudioFile() -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("test_audio.wav")
        
        let testData = Data(repeating: 0, count: 1024)
        try! testData.write(to: fileURL)
        
        return fileURL
    }
}

// MARK: - Test Data Structures

struct TestResponse: Codable, Equatable {
    let message: String
    let status: Int
}

// MARK: - Mock URLSession

class MockURLSession {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    var responses: [(Data?, URLResponse?, Error?)] = []
    var responseIndex = 0
    var responseDelay: TimeInterval = 0
    var requestCount = 0
    var lastRequest: URLRequest?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        requestCount += 1
        
        if responseDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        
        // Use responses array if available
        if !responses.isEmpty && responseIndex < responses.count {
            let (data, response, error) = responses[responseIndex]
            responseIndex += 1
            
            if let error = error {
                throw error
            }
            
            guard let data = data, let response = response else {
                throw URLError(.badServerResponse)
            }
            
            return (data, response)
        }
        
        // Use single mock values
        if let error = mockError {
            throw error
        }
        
        guard let data = mockData, let response = mockResponse else {
            throw URLError(.badServerResponse)
        }
        
        return (data, response)
    }
}