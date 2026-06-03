import Foundation
import CryptoKit

#if canImport(AdSupport)
    import AdSupport
#endif

#if canImport(UIKit)
    import UIKit
#endif

/// Generates user_hash for consent identity following the cross-platform SHA-256 recipe:
/// user_hash = SHA256(customer_id + ":" + consent_project_id + ":" + device_id)
/// On tvOS: device_id is IDFA (if available) or IDFV as fallback
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public final class UserHashGenerator {
    private static let fallbackDeviceId = UUID().uuidString

    /// Generate user_hash for the given customer_id, consent_project_id, and device identifier
    /// - Parameters:
    ///   - customerId: DataGrail customer ID (e.g., "cust-1")
    ///   - consentProjectId: Consent project ID (defaults to "default")
    ///   - deviceIdentifier: Optional device identifier override (if nil, auto-detect)
    /// - Returns: 64-character hex SHA-256 hash
    public static func generateUserHash(
        customerId: String,
        consentProjectId: String = "default",
        deviceIdentifier: String? = nil
    ) -> String {
        let deviceId = deviceIdentifier ?? getDeviceIdentifier()
        let input = "\(customerId):\(consentProjectId):\(deviceId)"

        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Get the device identifier for consent identity
    /// On tvOS: IDFA (if ATT granted) or IDFV fallback
    /// On iOS: IDFV (IDFA requires ATT prompt, which is out of scope for this SDK)
    private static func getDeviceIdentifier() -> String {
        #if os(tvOS)
            // tvOS: prefer IDFA if available (ATT permissioned), fallback to IDFV
            #if canImport(AdSupport)
                let idfa = ASIdentifierManager.shared().advertisingIdentifier
                if idfa != UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
                    return idfa.uuidString
                }
            #endif

            // Fallback to IDFV
            #if canImport(UIKit)
                if let idfv = UIDevice.current.identifierForVendor {
                    return idfv.uuidString
                }
            #endif

            Logger.warn("No stable device identifier available, using fallback UUID")
            return fallbackDeviceId

        #elseif os(iOS)
            // iOS: use IDFV (stable per-vendor, no ATT prompt needed)
            #if canImport(UIKit)
                if let idfv = UIDevice.current.identifierForVendor {
                    return idfv.uuidString
                }
            #endif

            Logger.warn("No IDFV available, using fallback UUID")
            return fallbackDeviceId

        #else
            return fallbackDeviceId
        #endif
    }
}
