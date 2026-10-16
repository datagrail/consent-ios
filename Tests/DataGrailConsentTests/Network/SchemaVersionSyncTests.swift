@testable import DataGrailConsent
import XCTest

/// Pins ConsentService.schemaVersion to the `package` of the dgapp consent_schema config.proto
/// vendored at consent_schema/, since nothing reads the proto at build time.
///
/// Exactly one vendored version is expected: it is the one this SDK reports. Once the SDK supports
/// more than one, this guard must name the reported version explicitly instead.
final class SchemaVersionSyncTests: XCTestCase {
    private static let bumpHint = "bump the vendored proto and the constant together"

    func testSchemaVersionMatchesVendoredProto() throws {
        let schemaRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Network
            .deletingLastPathComponent() // DataGrailConsentTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("consent_schema/proto/datagrail/consent")
        let fileManager = FileManager.default
        let versions = try fileManager.contentsOfDirectory(atPath: schemaRoot.path).filter {
            fileManager.fileExists(atPath: schemaRoot.appendingPathComponent("\($0)/config.proto").path)
        }
        XCTAssertEqual(
            versions.count,
            1,
            "Expected exactly one \(schemaRoot.path)/*/config.proto, found \(versions); \(Self.bumpHint)"
        )
        let directoryVersion = try XCTUnwrap(versions.first)

        let protoUrl = schemaRoot.appendingPathComponent("\(directoryVersion)/config.proto")
        let proto = try String(contentsOf: protoUrl, encoding: .utf8)
        let regex = try NSRegularExpression(
            pattern: #"^package datagrail\.consent\.(v[1-9][0-9]*);"#,
            options: .anchorsMatchLines
        )
        let nsProto = proto as NSString
        let match = try XCTUnwrap(
            regex.firstMatch(in: proto, range: NSRange(location: 0, length: nsProto.length)),
            "No `package datagrail.consent.vN;` in \(protoUrl.path); \(Self.bumpHint)"
        )
        let protoVersion = nsProto.substring(with: match.range(at: 1))

        XCTAssertEqual(
            protoVersion,
            directoryVersion,
            "\(protoUrl.path) declares \(protoVersion) but lives under \(directoryVersion); \(Self.bumpHint)"
        )
        XCTAssertEqual(
            ConsentService.schemaVersion,
            protoVersion,
            "ConsentService.schemaVersion is out of sync with \(protoUrl.path); \(Self.bumpHint)"
        )
    }
}
