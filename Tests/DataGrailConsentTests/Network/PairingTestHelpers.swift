@testable import DataGrailConsent
import Foundation

/// Extended mock network client for pairing tests
class MockNetworkClientForPairing: NetworkClient {
    var mockResponse: Data?
    var mockError: ConsentError?
    var lastRequest: URLRequest?
    var onRequest: (() -> Void)?

    override func request(
        url: URL,
        method: HTTPMethod = .get,
        body: Data? = nil,
        headers: [String: String]? = nil,
        completion: @escaping (Result<Data, ConsentError>) -> Void
    ) {
        var captured = URLRequest(url: url)
        captured.httpMethod = method.rawValue
        captured.httpBody = body
        headers?.forEach { captured.setValue($1, forHTTPHeaderField: $0) }
        lastRequest = captured
        onRequest?()

        if let error = mockError {
            DispatchQueue.global().async {
                completion(.failure(error))
            }
        } else if let response = mockResponse {
            DispatchQueue.global().async {
                completion(.success(response))
            }
        } else {
            DispatchQueue.global().async {
                completion(.success(Data()))
            }
        }
    }
}
