import Foundation

/// Result of polling the pairing endpoint
public enum PairingRead {
    case notFound  // Phone hasn't written yet
    case found(ConsentPreferences, updatedAt: String?)  // A record exists (updatedAt distinguishes new writes)
}

/// Service for QR pairing operations (no session subsystem, reads directly)
public final class PairingService {
    private let networkClient: NetworkClient
    private let apiBaseUrl: String
    private let apiKey: String?

    public init(networkClient: NetworkClient, apiBaseUrl: String = "https://consent.datagrail.io", apiKey: String? = nil) {
        self.networkClient = networkClient
        self.apiBaseUrl = apiBaseUrl
        self.apiKey = apiKey
    }

    // MARK: - QR URL Generation

    /// Build the QR target URL that the phone will open
    /// Format: {publicBaseUrl}/tv/?customer_id={id}&user_hash={hash}&config_url={encoded}
    /// - Parameters:
    ///   - publicBaseUrl: The base URL reachable by the phone (LAN or tunnel)
    ///   - customerId: DataGrail customer ID
    ///   - userHash: Device user_hash (64-char hex SHA-256)
    ///   - configUrl: URL to the consent config JSON
    /// - Returns: Full URL to encode in the QR code
    public func qrURL(publicBaseUrl: String, customerId: String, userHash: String, configUrl: String) -> URL? {
        var components = URLComponents(string: "\(publicBaseUrl)/tv/")
        components?.queryItems = [
            URLQueryItem(name: "customer_id", value: customerId),
            URLQueryItem(name: "user_hash", value: userHash),
            URLQueryItem(name: "config_url", value: configUrl),
        ]
        return components?.url
    }

    // MARK: - Consent Read (Polling)

    /// Fetch consent preferences for the given user_hash
    /// This is the polling endpoint the TV calls to detect when the phone has written.
    /// GET /universal_consent?customer_id={id}&user_hash={hash}
    /// - Parameters:
    ///   - customerId: DataGrail customer ID
    ///   - userHash: Device user_hash
    ///   - completion: Result with .notFound or .found(preferences)
    public func fetchConsent(
        customerId: String,
        userHash: String,
        completion: @escaping (Result<PairingRead, ConsentError>) -> Void
    ) {
        var components = URLComponents(string: "\(apiBaseUrl)/universal_consent")
        components?.queryItems = [
            URLQueryItem(name: "customer_id", value: customerId),
            URLQueryItem(name: "user_hash", value: userHash),
        ]

        guard let url = components?.url else {
            completion(.failure(.invalidConfiguration("Failed to build pairing read URL")))
            return
        }

        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Cache-Control": "no-cache",
        ]
        if let apiKey = apiKey {
            headers["X-DG-Api-Key"] = apiKey
        }

        networkClient.request(url: url, method: .get, body: nil, headers: headers) { result in
            switch result {
            case let .success(data):
                do {
                    let response = try JSONDecoder().decode(PairingReadResponse.self, from: data)
                    if response.status == "found", let prefs = response.consentPreferences {
                        completion(.success(.found(prefs, updatedAt: response.updatedAt)))
                    } else {
                        // status: "not_found"
                        completion(.success(.notFound))
                    }
                } catch {
                    completion(.failure(.networkError("Failed to decode pairing read response: \(error.localizedDescription)")))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}

/// Response from GET /universal_consent.
///
/// The Universal Consent API returns `cookieOptions` in canonical **map** form
/// (`{ "dg-category-x": bool }`) with a camelCase `isCustomised`, whereas the SDK's
/// `ConsentPreferences` models `cookieOptions` as an array of `CategoryConsent`.
/// This boundary type decodes the server shape and adapts it to the SDK model.
private struct PairingReadResponse: Decodable {
    let status: String  // "found" | "not_found"
    let consentPreferences: ConsentPreferences?
    let updatedAt: String?  // server-set timestamp; used to detect a NEW write

    enum CodingKeys: String, CodingKey {
        case status
        case consentPreferences = "consent_preferences"
        case updatedAt = "updated_at"
    }

    private struct ServerPreferences: Decodable {
        let isCustomised: Bool?
        let cookieOptions: [String: Bool]?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)

        if let server = try container.decodeIfPresent(ServerPreferences.self, forKey: .consentPreferences) {
            let options = (server.cookieOptions ?? [:]).map { CategoryConsent(gtmKey: $0.key, isEnabled: $0.value) }
            consentPreferences = ConsentPreferences(
                isCustomised: server.isCustomised ?? false,
                cookieOptions: options
            )
        } else {
            consentPreferences = nil
        }
    }
}
