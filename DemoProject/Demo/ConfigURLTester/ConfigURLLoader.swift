@_spi(Diagnostics) import DataGrailConsent
import Foundation

enum ArtifactMode: String {
    case test, live, other
}

struct ConfigURLMetadata: Equatable {
    /// `nil` for a legacy, unversioned `config.json` URL (treated as v1).
    let schemaVersion: String?
    let artifactMode: ArtifactMode
    /// Derived from the presign's `X-Amz-Date` + `X-Amz-Expires`, on the device clock.
    let expiresAt: Date?
}

enum ConfigURLLoadError: Error, Equatable {
    case invalidUrl
    case expired(expiresAt: Date?)
    case urlAltered
    case notFoundOrDenied(status: Int)
    case unreachable(String)
    case http(status: Int, code: String?)
    case unsupportedSchema(config: String, sdk: String)
    case parse(String)
}

struct LoadedConfig {
    let config: ConsentConfig
    let metadata: ConfigURLMetadata
}

/// Fetches a pre-signed config URL and decodes it with the SDK's own `ConsentConfig` model.
///
/// Deliberately bypasses `DataGrailConsent.initialize`: the SDK falls back to its cached config on
/// any fetch or parse failure (so an expired URL would silently render the previous config), would
/// treat the S3 host as the privacy domain, and discards the S3 error body we need to tell
/// "expired" apart from "altered".
struct ConfigURLLoader {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let requestTimeout: TimeInterval = 15
    private static let errorBodyLimit = 4096
    private static let parsePreviewLength = 200
    private static let alteredCodes: Set<String> = [
        "SignatureDoesNotMatch", "AuthorizationQueryParametersError", "InvalidToken",
    ]

    let sdkSchemaVersion: String
    let now: () -> Date
    let transport: Transport

    init(
        sdkSchemaVersion: String = DataGrailConsent.schemaVersion,
        now: @escaping () -> Date = Date.init,
        transport: @escaping Transport = ConfigURLLoader.urlSessionTransport
    ) {
        self.sdkSchemaVersion = sdkSchemaVersion
        self.now = now
        self.transport = transport
    }

    static func validatedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    static func metadata(for url: URL) -> ConfigURLMetadata {
        let path = url.path
        let artifactMode: ArtifactMode
        if path.hasPrefix("/mobile-test/") {
            artifactMode = .test
        } else if path.hasPrefix("/mobile-live/") {
            artifactMode = .live
        } else {
            artifactMode = .other
        }
        return ConfigURLMetadata(
            schemaVersion: firstCapture(of: #"config\.(v\d+)\.json$"#, in: path),
            artifactMode: artifactMode,
            expiresAt: expiresAt(for: url)
        )
    }

    func load(_ raw: String) async -> Result<LoadedConfig, ConfigURLLoadError> {
        guard let url = Self.validatedURL(raw) else { return .failure(.invalidUrl) }
        let metadata = Self.metadata(for: url)

        if let configVersion = metadata.schemaVersion, configVersion != sdkSchemaVersion {
            return .failure(.unsupportedSchema(config: configVersion, sdk: sdkSchemaVersion))
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "GET"

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            return .failure(.unreachable(error.localizedDescription))
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            return .failure(classify(status: response.statusCode, body: data, expiresAt: metadata.expiresAt))
        }

        // Mirrors the SDK's own decode in ConfigService.fetchConfig.
        do {
            let config = try JSONDecoder().decode(ConsentConfig.self, from: data)
            return .success(LoadedConfig(config: config, metadata: metadata))
        } catch {
            let preview = String(decoding: data.prefix(Self.parsePreviewLength), as: UTF8.self)
            return .failure(.parse("Parse failed (\(data.count) bytes): \(preview)"))
        }
    }

    /// S3's error code is authoritative; the device-clock expiry is only a tiebreaker for a bare 403.
    private func classify(status: Int, body: Data, expiresAt: Date?) -> ConfigURLLoadError {
        let xml = String(decoding: body.prefix(Self.errorBodyLimit), as: UTF8.self)
        let code = Self.firstCapture(of: "<Code>([^<]*)</Code>", in: xml)
        let message = Self.firstCapture(of: "<Message>([^<]*)</Message>", in: xml) ?? ""

        if code == "ExpiredToken" || (code == "AccessDenied" && message.localizedCaseInsensitiveContains("expired")) {
            return .expired(expiresAt: expiresAt)
        }
        if let code = code, Self.alteredCodes.contains(code) {
            return .urlAltered
        }
        if status == 403, let expiresAt = expiresAt, expiresAt < now() {
            return .expired(expiresAt: expiresAt)
        }
        if status == 403 || status == 404 || code == "NoSuchKey" {
            return .notFoundOrDenied(status: status)
        }
        return .http(status: status, code: code)
    }

    private static func expiresAt(for url: URL) -> Date? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let dateString = items.first(where: { $0.name == "X-Amz-Date" })?.value,
              let expiresString = items.first(where: { $0.name == "X-Amz-Expires" })?.value,
              let seconds = TimeInterval(expiresString),
              let signedAt = amzDateFormatter.date(from: dateString)
        else { return nil }
        return signedAt.addingTimeInterval(seconds)
    }

    private static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static func firstCapture(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: configuration)
    }()
}

extension ConfigURLLoadError {
    var userFacing: (title: String, body: String) {
        switch self {
        case .invalidUrl:
            return ("Not a valid config URL",
                    "Paste the full https:// link from the Mobile tab's View config link.")
        case let .expired(expiresAt):
            var body = "Test URLs are valid for 15 minutes. In the Mobile tab, reload the test config panel "
                + "to get a fresh link, then paste it here."
            if let expiresAt = expiresAt {
                body += "\n\nExpired at \(DateFormatter.localizedString(from: expiresAt, dateStyle: .short, timeStyle: .medium))."
            }
            return ("Test URL expired", body)
        case .urlAltered:
            return ("URL was changed or cut off",
                    "The link's signature doesn't match; it was probably truncated when copied. Copy the whole link again.")
        case .notFoundOrDenied:
            return ("Config not found",
                    "This test config no longer exists (test configs are deleted after 7 days) or access was denied. "
                        + "Publish a new test config.")
        case let .unreachable(detail):
            return ("Couldn't reach the config",
                    "Check the device's internet connection and try again. (\(detail))")
        case let .http(status, code):
            return ("Unexpected response", "HTTP \(status)\(code.map { " – \($0)" } ?? "").")
        case let .unsupportedSchema(config, sdk):
            return ("Unsupported schema version",
                    "This config uses schema \(config). This test app (SDK \(DataGrailConsent.sdkVersion)) renders "
                        + "schema \(sdk). Select a \(sdk) target in the Mobile tab, or use a test app built for \(config).")
        case let .parse(detail):
            return ("Config couldn't be read",
                    "\(detail)\n\nReport this to support with the schema version shown above.")
        }
    }
}
