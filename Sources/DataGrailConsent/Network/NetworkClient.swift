import Foundation

/// HTTP methods supported by the network client
public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Network client for making HTTP requests with retry support
public class NetworkClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Make an HTTP request
    /// - Parameters:
    ///   - url: The URL to request
    ///   - method: The HTTP method
    ///   - body: Optional request body data
    ///   - headers: Optional HTTP headers
    ///   - completion: Completion handler with result
    public func request(
        url: URL,
        method: HTTPMethod = .get,
        body: Data? = nil,
        headers: [String: String]? = nil,
        completion: @escaping (Result<Data, ConsentError>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        // Set headers
        if let headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Set default content type for POST/PUT
        if body != nil, request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.networkError("Invalid response type")))
                return
            }

            let statusCode = httpResponse.statusCode
            let dataSize = data?.count ?? 0

            // Handle 304 Not Modified - return empty data to trigger cache usage
            // Check this BEFORE checking for nil data, since 304 responses have no body
            if statusCode == 304 {
                completion(.success(Data()))
                return
            }

            guard (200 ... 299).contains(statusCode) else {
                completion(.failure(.networkError("HTTP \(statusCode), data: \(dataSize) bytes")))
                return
            }

            guard let data else {
                completion(.failure(.networkError("No data received for HTTP \(statusCode)")))
                return
            }

            completion(.success(data))
        }

        task.resume()
    }

    /// Retry an operation with exponential backoff
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retry attempts (default: 5)
    ///   - baseDelay: Base delay in seconds (default: 0.25)
    ///   - operation: The operation to retry
    ///   - completion: Completion handler with result
    public func retryWithBackoff<T>(
        maxAttempts: Int = 5,
        baseDelay: TimeInterval = 0.25,
        operation: @escaping (@escaping (Result<T, ConsentError>) -> Void) -> Void,
        completion: @escaping (Result<T, ConsentError>) -> Void
    ) {
        func attempt(_ attemptNumber: Int) {
            operation { result in
                switch result {
                case let .success(value):
                    completion(.success(value))

                case let .failure(error):
                    if attemptNumber >= maxAttempts {
                        completion(.failure(error))
                        return
                    }

                    let delay = baseDelay * pow(2.0, Double(attemptNumber))

                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        attempt(attemptNumber + 1)
                    }
                }
            }
        }

        attempt(1)
    }
}
