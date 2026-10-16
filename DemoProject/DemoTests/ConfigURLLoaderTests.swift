@testable import Demo
import XCTest

final class ConfigURLLoaderTests: XCTestCase {
    private let testURL = "https://bucket.s3.amazonaws.com/mobile-test/uuid/42/config.v1.json"
        + "?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20260924T101500Z&X-Amz-Expires=900"
        + "&X-Amz-SignedHeaders=host&X-Amz-Signature=abc"
    /// 2026-09-24T10:30:00Z, the expiry encoded in `testURL`.
    private let expiry = Date(timeIntervalSince1970: 1_790_245_800)

    // MARK: - validatedURL

    func testValidatedURLTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(ConfigURLLoader.validatedURL("  \(testURL)\n")?.absoluteString, testURL)
    }

    func testValidatedURLRejectsNonHTTPSAndMalformedInput() {
        XCTAssertNil(ConfigURLLoader.validatedURL("http://bucket.s3.amazonaws.com/config.v1.json"))
        XCTAssertNil(ConfigURLLoader.validatedURL("not a url"))
        XCTAssertNil(ConfigURLLoader.validatedURL("https://"))
        XCTAssertNil(ConfigURLLoader.validatedURL(""))
    }

    // MARK: - metadata

    func testMetadataForPresignedTestURL() throws {
        let url = try XCTUnwrap(URL(string: testURL))
        XCTAssertEqual(
            ConfigURLLoader.metadata(for: url),
            ConfigURLMetadata(schemaVersion: "v1", artifactMode: .test, expiresAt: expiry)
        )
    }

    func testMetadataForLiveURL() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/mobile-live/uuid/7/default/config.v1.json"))
        XCTAssertEqual(ConfigURLLoader.metadata(for: url).artifactMode, .live)
    }

    func testMetadataForLegacyURLHasNoSchemaVersion() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/uuid/config.json"))
        let metadata = ConfigURLLoader.metadata(for: url)
        XCTAssertNil(metadata.schemaVersion)
        XCTAssertEqual(metadata.artifactMode, .other)
    }

    func testMetadataExpiryIsNilWhenAmzDateMissingOrGarbage() throws {
        let missing = try XCTUnwrap(URL(string: "https://h.example.com/mobile-test/u/1/config.v1.json?X-Amz-Expires=900"))
        let garbage = try XCTUnwrap(URL(string: "https://h.example.com/mobile-test/u/1/config.v1.json?X-Amz-Date=nope&X-Amz-Expires=900"))
        XCTAssertNil(ConfigURLLoader.metadata(for: missing).expiresAt)
        XCTAssertNil(ConfigURLLoader.metadata(for: garbage).expiresAt)
    }

    // MARK: - load: pre-fetch failures

    func testInvalidURLFails() async {
        let result = await loader(status: 200, body: Data()).load("not a url")
        XCTAssertEqual(result.error, .invalidUrl)
    }

    func testSchemaGateRejectsV2WithoutFetching() async {
        var calls = 0
        let loader = ConfigURLLoader(sdkSchemaVersion: "v1", now: { self.expiry }, transport: { request in
            calls += 1
            return (Data(), Self.response(200, request))
        })
        let result = await loader.load(testURL.replacingOccurrences(of: "config.v1.json", with: "config.v2.json"))
        XCTAssertEqual(result.error, .unsupportedSchema(config: "v2", sdk: "v1"))
        XCTAssertEqual(calls, 0)
    }

    // MARK: - load: success

    func testLoadsFixtureConfig() async throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "test-config", withExtension: "json"))
        let fixture = try Data(contentsOf: fixtureURL)
        let result = await loader(status: 200, body: fixture).load(testURL)
        let loaded = try result.get()
        XCTAssertEqual(loaded.config.version, "cc959465-747d-4c81-8bc1-5dcd34dc3756")
        XCTAssertEqual(loaded.metadata, ConfigURLMetadata(schemaVersion: "v1", artifactMode: .test, expiresAt: expiry))
    }

    // MARK: - load: HTTP error classification

    func testAccessDeniedRequestHasExpiredIsExpired() async {
        let body = s3Error("AccessDenied", "Request has expired")
        let result = await loader(status: 403, body: body, now: expiry.addingTimeInterval(-60)).load(testURL)
        XCTAssertEqual(result.error, .expired(expiresAt: expiry))
    }

    func testBare403AfterLocalExpiryIsExpired() async {
        let body = s3Error("AccessDenied", "Access Denied")
        let result = await loader(status: 403, body: body, now: expiry.addingTimeInterval(60)).load(testURL)
        XCTAssertEqual(result.error, .expired(expiresAt: expiry))
    }

    func testBare403BeforeLocalExpiryIsNotFoundOrDenied() async {
        let body = s3Error("AccessDenied", "Access Denied")
        let result = await loader(status: 403, body: body, now: expiry.addingTimeInterval(-60)).load(testURL)
        XCTAssertEqual(result.error, .notFoundOrDenied(status: 403))
    }

    func testExpiredTokenIsExpired() async {
        let result = await loader(status: 400, body: s3Error("ExpiredToken", "The provided token has expired.")).load(testURL)
        XCTAssertEqual(result.error, .expired(expiresAt: expiry))
    }

    func testSignatureDoesNotMatchIsURLAltered() async {
        let result = await loader(status: 403, body: s3Error("SignatureDoesNotMatch", "sig")).load(testURL)
        XCTAssertEqual(result.error, .urlAltered)
    }

    /// Editing `X-Amz-Expires` breaks the signature; S3's code must win over the local-clock tiebreak.
    func testSignatureDoesNotMatchWinsOverLocalExpiry() async {
        let body = s3Error("SignatureDoesNotMatch", "sig")
        let result = await loader(status: 403, body: body, now: expiry.addingTimeInterval(60)).load(testURL)
        XCTAssertEqual(result.error, .urlAltered)
    }

    func testNoSuchKeyIsNotFoundOrDenied() async {
        let result = await loader(status: 404, body: s3Error("NoSuchKey", "The specified key does not exist.")).load(testURL)
        XCTAssertEqual(result.error, .notFoundOrDenied(status: 404))
    }

    func testServerErrorIsHTTP() async {
        let result = await loader(status: 500, body: Data()).load(testURL)
        XCTAssertEqual(result.error, .http(status: 500, code: nil))
    }

    func testTransportErrorIsUnreachable() async {
        let loader = ConfigURLLoader(sdkSchemaVersion: "v1", now: { self.expiry }, transport: { _ in
            throw URLError(.notConnectedToInternet)
        })
        guard case .unreachable = await loader.load(testURL).error else {
            return XCTFail("expected .unreachable")
        }
    }

    // MARK: - load: decode failures

    func testUnrecognizedJSONIsParseErrorWithPreview() async {
        let result = await loader(status: 200, body: Data(#"{"foo":1}"#.utf8)).load(testURL)
        guard case let .parse(detail) = result.error else { return XCTFail("expected .parse") }
        XCTAssertTrue(detail.contains(#"{"foo":1}"#))
    }

    func testEmptyBodyIsParseError() async {
        guard case .parse = await loader(status: 200, body: Data()).load(testURL).error else {
            return XCTFail("expected .parse")
        }
    }

    /// An ungated v2 body (legacy URL, so no schema gate) must still fail safely.
    func testV2BodyBehindLegacyURLIsParseError() async {
        let v2Body = Data(#"{"version":"x","publishedAtMs":1,"defaultCookieBehavior":"a","layout":{}}"#.utf8)
        let result = await loader(status: 200, body: v2Body).load("https://cdn.example.com/uuid/config.json")
        guard case .parse = result.error else { return XCTFail("expected .parse") }
    }

    // MARK: - copy

    func testExpiredCopyMentionsFifteenMinutes() {
        XCTAssertTrue(ConfigURLLoadError.expired(expiresAt: nil).userFacing.body.contains("15 minutes"))
    }

    // MARK: - Helpers

    private func loader(status: Int, body: Data, now: Date? = nil) -> ConfigURLLoader {
        let clock = now ?? expiry.addingTimeInterval(-60)
        return ConfigURLLoader(sdkSchemaVersion: "v1", now: { clock }, transport: { request in
            (body, Self.response(status, request))
        })
    }

    private func s3Error(_ code: String, _ message: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Error><Code>\(code)</Code><Message>\(message)</Message><RequestId>r</RequestId></Error>
        """.utf8)
    }

    private static func response(_ status: Int, _ request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil)
            ?? HTTPURLResponse()
    }
}

private extension Result {
    var error: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
