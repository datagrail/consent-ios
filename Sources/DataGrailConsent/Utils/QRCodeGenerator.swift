#if canImport(CoreImage) && canImport(UIKit)
    import CoreImage
    import UIKit

    /// Generates QR code images using Core Image (zero external dependencies)
    public final class QRCodeGenerator {
        /// Generate a QR code image from a URL string
        /// - Parameters:
        ///   - urlString: The URL to encode in the QR code
        ///   - size: The desired output size (QR will be square)
        /// - Returns: UIImage containing the QR code, or nil if generation fails
        public static func generateQRCode(from urlString: String, size: CGFloat = 200) -> UIImage? {
            let data = Data(urlString.utf8)

            guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
                return nil
            }

            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("H", forKey: "inputCorrectionLevel")  // High error correction

            guard let ciImage = filter.outputImage else {
                return nil
            }

            // Scale up the QR code (default output is small)
            let transform = CGAffineTransform(scaleX: size / ciImage.extent.width, y: size / ciImage.extent.height)
            let scaledImage = ciImage.transformed(by: transform)

            // Convert to UIImage
            let context = CIContext()
            guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
                return nil
            }

            return UIImage(cgImage: cgImage)
        }
    }
#endif
