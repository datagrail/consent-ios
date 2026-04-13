import Foundation
import WebKit
import DataGrailConsent

/// Helper for injecting DataGrail consent preferences into WKWebViews
class DataGrailWebViewHelper {

    /// Inject consent preferences into a WebView
    /// Call this in WKNavigationDelegate's didFinish callback after page loads
    /// - Parameter webView: The WKWebView to inject into
    static func injectConsentPreferences(into webView: WKWebView) {
        guard let preferences = try? DataGrailConsent.shared.getCategories() else {
            return
        }

        guard let script = createInjectionScript(preferences: preferences) else {
            return
        }

        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("[DataGrail iOS SDK] Injection error: \(error.localizedDescription)")
            }
        }
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
            try {
                const preferences = \(preferencesJSON);
                const config = { "runPreferenceCallbacks": false };

                // Store preferences globally for debugging
                window.datagrailConsent = preferences;
                console.log('[DataGrail iOS SDK] Preferences stored in window.datagrailConsent:', JSON.stringify(preferences));

                // Try to set preferences via API if available
                if (window.DG_BANNER_API && typeof window.DG_BANNER_API.setConsentPreferences === 'function') {
                    console.log('[DataGrail iOS SDK] Calling DG_BANNER_API.setConsentPreferences...');
                    try {
                        const result = window.DG_BANNER_API.setConsentPreferences(preferences, config);
                        console.log('[DataGrail iOS SDK] setConsentPreferences called successfully, result:', result);
                    } catch (apiError) {
                        console.error('[DataGrail iOS SDK] setConsentPreferences threw error:', apiError.message);
                    }
                } else {
                    console.log('[DataGrail iOS SDK] DG_BANNER_API not available (type=' + typeof window.DG_BANNER_API + ')');
                }
            } catch (error) {
                console.error('[DataGrail iOS SDK] Error injecting consent:', error.message, error.stack);
            }
        })();
        """

        return script
    }
}
