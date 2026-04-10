import Foundation
import WebKit
import DataGrailConsent

/// Helper for injecting DataGrail consent preferences into WKWebViews
class DataGrailWebViewHelper {

    /// Inject consent preferences into a WebView configuration
    /// Call this before loading web content
    /// - Parameter configuration: The WKWebViewConfiguration to inject into
    static func injectConsentPreferences(into configuration: WKWebViewConfiguration) {
        guard let preferences = try? DataGrailConsent.shared.getCategories() else {
            return
        }

        guard let script = createInjectionScript(preferences: preferences) else {
            return
        }

        let userScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )

        configuration.userContentController.addUserScript(userScript)
    }

    /// Update consent preferences in an already-loaded WebView
    /// - Parameters:
    ///   - webView: The WebView to update
    ///   - completion: Called with true if successful, false otherwise
    static func updateConsentPreferences(
        in webView: WKWebView,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let preferences = try? DataGrailConsent.shared.getCategories() else {
            completion?(false)
            return
        }

        guard let script = createInjectionScript(preferences: preferences) else {
            completion?(false)
            return
        }

        webView.evaluateJavaScript(script) { _, error in
            completion?(error == nil)
        }
    }

    /// Create JavaScript to inject consent preferences
    private static func createInjectionScript(preferences: ConsentPreferences) -> String? {
        let encoder = JSONEncoder()
        guard let preferencesData = try? encoder.encode(preferences),
              let preferencesJSON = String(data: preferencesData, encoding: .utf8) else {
            return nil
        }

        // Create the injection script that calls DG_BANNER_API.setConsentPreferences
        let script = """
        (function() {
            const preferences = \(preferencesJSON);
            const config = { "runPreferenceCallbacks": false };

            // Store preferences globally for debugging
            window.datagrailConsent = preferences;

            // If DG_BANNER_API is available, use it to set preferences
            if (window.DG_BANNER_API && typeof window.DG_BANNER_API.setConsentPreferences === 'function') {
                window.DG_BANNER_API.setConsentPreferences(preferences, config);
                console.log('[DataGrail iOS SDK] Set consent preferences via DG_BANNER_API');
            } else {
                console.log('[DataGrail iOS SDK] DG_BANNER_API not available, preferences stored in window.datagrailConsent');
            }
        })();
        """

        return script
    }
}
