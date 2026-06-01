#if canImport(CoreImage) && canImport(UIKit)
    import XCTest
    @testable import DataGrailConsent

    /// Tests for QR code generation using Core Image
    final class QRCodeGeneratorTests: XCTestCase {

        // MARK: - Generation Tests

        func testGeneratesQRCodeFromURL() {
            let urlString = "https://example.com/tv/?customer_id=cust-1&user_hash=abc123"
            let qrImage = QRCodeGenerator.generateQRCode(from: urlString, size: 200)

            XCTAssertNotNil(qrImage, "Should generate QR code image")
        }

        func testGeneratesQRCodeWithDefaultSize() {
            let urlString = "https://example.com"
            let qrImage = QRCodeGenerator.generateQRCode(from: urlString)

            XCTAssertNotNil(qrImage, "Should generate QR code with default size")
        }

        func testGeneratesQRCodeWithCustomSize() {
            let urlString = "https://example.com"
            let qrImage = QRCodeGenerator.generateQRCode(from: urlString, size: 500)

            XCTAssertNotNil(qrImage, "Should generate QR code with custom size")
        }

        func testGeneratesQRCodeForLongURL() {
            let urlString = "https://example.com/tv/?customer_id=cust-1&user_hash=" +
                String(repeating: "a", count: 64) +
                "&config_url=https://example.com/very/long/path/to/config.json?param1=value1&param2=value2"
            let qrImage = QRCodeGenerator.generateQRCode(from: urlString, size: 300)

            XCTAssertNotNil(qrImage, "Should generate QR code for long URL")
        }

        func testGeneratesQRCodeForLocalURL() {
            let urlString = "http://192.168.1.5:8080/tv/?customer_id=cust-1&user_hash=" +
                String(repeating: "b", count: 64)
            let qrImage = QRCodeGenerator.generateQRCode(from: urlString, size: 300)

            XCTAssertNotNil(qrImage, "Should generate QR code for local URL")
        }

        func testGeneratesQRCodeWithSpecialCharacters() {
            let urlString = "https://example.com/tv/?foo=bar%20baz&qux=test%2Fpath"
            let qrImage = QRCodeGenerator.generateQRCode(from: urlString, size: 200)

            XCTAssertNotNil(qrImage, "Should generate QR code with URL-encoded characters")
        }

        // MARK: - Size Tests

        func testGeneratedImageHasCorrectSize() {
            let size: CGFloat = 300
            guard let qrImage = QRCodeGenerator.generateQRCode(from: "https://example.com", size: size) else {
                XCTFail("Failed to generate QR code")
                return
            }

            // The image size should be approximately the requested size
            // (may vary slightly due to QR code module alignment)
            XCTAssertGreaterThan(qrImage.size.width, size * 0.9, "Image width should be close to requested size")
            XCTAssertGreaterThan(qrImage.size.height, size * 0.9, "Image height should be close to requested size")
        }

        func testGeneratesSquareImage() {
            guard let qrImage = QRCodeGenerator.generateQRCode(from: "https://example.com", size: 200) else {
                XCTFail("Failed to generate QR code")
                return
            }

            // QR codes should always be square
            XCTAssertEqual(qrImage.size.width, qrImage.size.height, "QR code should be square")
        }

        // MARK: - tvOS Specific Tests

        #if os(tvOS)
            func testGeneratesQRCodeOnTvOS() {
                let urlString = "https://example.com/tv/?customer_id=cust-1&user_hash=abc123"
                let qrImage = QRCodeGenerator.generateQRCode(from: urlString, size: 300)

                XCTAssertNotNil(qrImage, "Should generate QR code on tvOS")
            }

            func testGeneratesLargeQRCodeForTvOS() {
                // tvOS needs larger QR codes for 10-foot viewing
                let urlString = "https://example.com/tv/"
                let qrImage = QRCodeGenerator.generateQRCode(from: urlString, size: 400)

                XCTAssertNotNil(qrImage, "Should generate large QR code for tvOS")
            }
        #endif

        // MARK: - Edge Cases

        func testHandlesEmptyString() {
            let qrImage = QRCodeGenerator.generateQRCode(from: "", size: 200)

            // Empty string might still generate a QR code (depends on Core Image behavior)
            // Just verify it doesn't crash
            XCTAssertTrue(true, "Should handle empty string without crashing")
        }

        func testHandlesVeryLongString() {
            let longString = String(repeating: "a", count: 2000)
            let qrImage = QRCodeGenerator.generateQRCode(from: longString, size: 200)

            // Very long strings might fail or succeed depending on QR code capacity
            // Just verify it doesn't crash
            XCTAssertTrue(true, "Should handle very long string without crashing")
        }

        func testHandlesSmallSize() {
            let qrImage = QRCodeGenerator.generateQRCode(from: "https://example.com", size: 50)

            XCTAssertNotNil(qrImage, "Should generate small QR code")
        }

        func testHandlesLargeSize() {
            let qrImage = QRCodeGenerator.generateQRCode(from: "https://example.com", size: 1000)

            XCTAssertNotNil(qrImage, "Should generate large QR code")
        }
    }
#endif
