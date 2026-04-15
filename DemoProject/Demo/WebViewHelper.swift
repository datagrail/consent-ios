import Foundation
import WebKit
import DataGrailConsent

/// Helper for injecting DataGrail consent preferences into WKWebViews via cookies
/// Configuration is automatically pulled from DataGrailConsent.shared
class DataGrailWebViewHelper {

    // MARK: - User UUID Management

    private static let userUUIDKey = "datagrail_user_uuid"

    // MARK: - Configuration Helpers

    /// Get customer ID from SDK config
    private static func getCustomerId() -> String? {
        return DataGrailConsent.shared.getConfig()?.dgCustomerId
    }

    /// Get config version from SDK config
    private static func getVersion() -> String? {
        return DataGrailConsent.shared.getConfig()?.version
    }

    /// Check if cross-subdomain cookies are enabled
    private static func isCrossSubdomainEnabled() -> Bool {
        return DataGrailConsent.shared.getConfig()?.plugins.allCookieSubdomains ?? false
    }

    /// Extract cookie domain from a URL
    /// - Parameter url: The URL to extract domain from
    /// - Returns: Cookie domain string (with leading dot if cross-subdomain is enabled)
    private static func getCookieDomain(for url: URL) -> String? {
        guard let host = url.host else { return nil }

        let crossSubdomain = isCrossSubdomainEnabled()

        // If cross-subdomain is enabled, add leading dot to set cookie for all subdomains
        // Extract root domain (e.g., "www.example.com" -> "example.com")
        if crossSubdomain {
            let components = host.split(separator: ".")
            // If we have at least 2 components (e.g., ["example", "com"]), use last 2
            if components.count >= 2 {
                let rootDomain = components.suffix(2).joined(separator: ".")
                return ".\(rootDomain)"
            }
        }

        return host
    }

    // MARK: - Cookie Names

    private static func preferencesCookieName() -> String {
        isCrossSubdomainEnabled() ? "datagrail_consent_preferences_s" : "datagrail_consent_preferences"
    }

    private static func idCookieName() -> String {
        isCrossSubdomainEnabled() ? "datagrail_consent_id_s" : "datagrail_consent_id"
    }

    private static func versionCookieName() -> String {
        isCrossSubdomainEnabled() ? "datagrail_consent_version_s" : "datagrail_consent_version"
    }

    // MARK: - Public API

    /// Injects DataGrail consent cookies into the webview for a specific URL
    /// - Parameters:
    ///   - webView: The WKWebView to inject cookies into
    ///   - url: The URL that will be loaded (used to determine cookie domain)
    ///   - completion: Called when cookies are injected or if an error occurs
    static func injectConsentCookies(
        into webView: WKWebView,
        for url: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Ensure SDK is initialized
        guard DataGrailConsent.shared.getConfig() != nil else {
            let error = NSError(
                domain: "DataGrail",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "DataGrailConsent SDK not initialized. Call DataGrailConsent.shared.initialize() first."]
            )
            completion(.failure(error))
            return
        }

        // Get current consent preferences from SDK
        guard let preferences = try? DataGrailConsent.shared.getCategories() else {
            let error = NSError(
                domain: "DataGrail",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get consent preferences from SDK"]
            )
            completion(.failure(error))
            return
        }

        // Get version from config
        guard let version = getVersion() else {
            let error = NSError(
                domain: "DataGrail",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get version from SDK config"]
            )
            completion(.failure(error))
            return
        }

        // Inject cookies with the version from config
        injectCookiesWithVersion(
            into: webView,
            for: url,
            preferences: preferences,
            version: version,
            completion: completion
        )
    }

    /// Convenience method to inject cookies and load a URL
    /// - Parameters:
    ///   - webView: The WKWebView to configure and load
    ///   - url: The URL to load after cookies are injected
    ///   - completion: Called with success or failure
    static func loadWebViewWithConsent(
        webView: WKWebView,
        url: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        injectConsentCookies(into: webView, for: url) { result in
            switch result {
            case .success:
                // Cookies injected successfully, now load the page
                let request = URLRequest(url: url)
                webView.load(request)
                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Update consent cookies in an already-loaded WebView
    /// Call this when consent preferences change
    /// - Parameters:
    ///   - webView: The WebView to update
    ///   - completion: Called with success or failure
    static func updateConsentCookies(
        in webView: WKWebView,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Use the current URL from the WebView
        guard let currentURL = webView.url else {
            let error = NSError(
                domain: "DataGrail",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "WebView has no current URL"]
            )
            completion(.failure(error))
            return
        }

        injectConsentCookies(into: webView, for: currentURL, completion: completion)
    }

    // MARK: - Private Methods - Cookie Injection

    /// Injects cookies with a specific version
    private static func injectCookiesWithVersion(
        into webView: WKWebView,
        for url: URL,
        preferences: ConsentPreferences,
        version: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        // Get cookie domain from URL
        let cookieDomain = getCookieDomain(for: url)

        var cookies: [HTTPCookie] = []

        // 1. Consent Preferences Cookie
        let preferencesValue = buildPreferencesString(from: preferences)
        if let cookie = createCookie(
            name: preferencesCookieName(),
            value: preferencesValue,
            domain: cookieDomain,
            expires: expiryDate
        ) {
            cookies.append(cookie)
        }

        // 2. User ID Cookie
        guard let userIdValue = buildConsentID() else {
            let error = NSError(
                domain: "DataGrail",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to build consent ID"]
            )
            completion(.failure(error))
            return
        }

        if let cookie = createCookie(
            name: idCookieName(),
            value: userIdValue,
            domain: cookieDomain,
            expires: expiryDate
        ) {
            cookies.append(cookie)
        }

        // 3. Version Cookie
        if let cookie = createCookie(
            name: versionCookieName(),
            value: version,
            domain: cookieDomain,
            expires: expiryDate
        ) {
            cookies.append(cookie)
        }

        // Inject all cookies asynchronously
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(.success(()))
        }
    }

    // MARK: - Private Methods - Cookie Building

    /// Gets or generates a persistent user UUID
    private static func getUserUUID() -> String {
        // Check if we already have a UUID stored
        if let existingUUID = UserDefaults.standard.string(forKey: userUUIDKey) {
            return existingUUID
        }

        // Generate new UUID v4 (lowercase to match JS crypto.randomUUID())
        let newUUID = UUID().uuidString.lowercased()

        // Persist it for future use
        UserDefaults.standard.set(newUUID, forKey: userUUIDKey)

        return newUUID
    }

    /// Builds the datagrail_consent_id cookie value
    /// Format: "{customerId}.{userUUID}"
    private static func buildConsentID() -> String? {
        guard let customerId = getCustomerId() else { return nil }
        let userUUID = getUserUUID()
        return "\(customerId).\(userUUID)"
    }

    /// Builds the preferences cookie value from ConsentPreferences
    /// Format: "gtm_key1:1|gtm_key2:0|gtm_key3:1"
    private static func buildPreferencesString(from preferences: ConsentPreferences) -> String {
        return preferences.cookieOptions
            .map { "\($0.gtmKey):\($0.isEnabled ? "1" : "0")" }
            .joined(separator: "|")
    }

    /// Helper to create an HTTPCookie with proper attributes
    private static func createCookie(name: String, value: String, domain: String?, expires: Date) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .path: "/",
            .expires: expires
        ]

        // Add domain if provided
        if let domain = domain {
            properties[.domain] = domain
        }

        // Note: WKWebView doesn't support .sameSitePolicy property via HTTPCookie
        // The banner expects SameSite=Strict but will accept Lax (WKWebView default)

        return HTTPCookie(properties: properties)
    }
}
