@testable import DataGrailConsent
import Foundation

/// Extended mock network client for pairing tests
class MockNetworkClientForPairing: NetworkClient {
    var mockResponse: Data?
    var mockError: ConsentError?
    var lastRequest: URLRequest?
    var onRequest: (() -> Void)?

    override func performRequest(
        _ request: URLRequest,
        completion: @escaping (Result<Data, ConsentError>) -> Void
    ) {
        lastRequest = request
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
