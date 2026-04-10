import SwiftUI
import WebKit
import DataGrailConsent

@available(iOS 14.0, *)
struct WebViewDemoView: View {
    @State private var urlText = "https://datagrail.io"
    @State private var logMessages: [String] = []
    @State private var webView: WKWebView?

    var body: some View {
        VStack(spacing: 0) {
            // URL Bar
            HStack {
                TextField("Enter URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Button("Go") {
                    loadURL()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.top)

            // Test Buttons
            HStack(spacing: 8) {
                Button("Get Preferences") {
                    getConsentPreferences()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Button("Check API") {
                    checkBannerAPI()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // WebView
            WebViewContainer(
                urlString: $urlText,
                webView: $webView,
                onLog: { message in
                    logMessages.append(message)
                }
            )

            // Log Console
            GroupBox {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logMessages.enumerated()), id: \.offset) { _, message in
                            Text(message)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 150)
            } label: {
                HStack {
                    Label("Console Log", systemImage: "terminal")
                    Spacer()
                    Button("Clear") {
                        logMessages.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding()
        }
        .navigationTitle("WebView Demo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadURL() {
        logMessages.append("Loading URL: \(urlText)")
    }

    private func getConsentPreferences() {
        guard let webView = webView else {
            logMessages.append("[Test] WebView not ready")
            return
        }

        logMessages.append("[Test] Calling DG_BANNER_API.getConsentPreferences()...")

        let script = """
        (function() {
            if (window.DG_BANNER_API && typeof window.DG_BANNER_API.getConsentPreferences === 'function') {
                const prefs = window.DG_BANNER_API.getConsentPreferences();
                return JSON.stringify(prefs, null, 2);
            } else {
                return "DG_BANNER_API.getConsentPreferences() not available";
            }
        })();
        """

        webView.evaluateJavaScript(script) { [self] result, error in
            if let error = error {
                logMessages.append("[Test] Error: \(error.localizedDescription)")
            } else if let result = result as? String {
                logMessages.append("[Test] DG_BANNER_API.getConsentPreferences():")
                result.split(separator: "\n").forEach { line in
                    logMessages.append("[Test]   \(line)")
                }
            }
        }
    }

    private func checkBannerAPI() {
        guard let webView = webView else {
            logMessages.append("[Test] WebView not ready")
            return
        }

        logMessages.append("[Test] Checking DG_BANNER_API availability...")

        let script = """
        (function() {
            const checks = {
                hasDG_BANNER_API: typeof window.DG_BANNER_API !== 'undefined',
                hasGetConsentPreferences: typeof window.DG_BANNER_API?.getConsentPreferences === 'function',
                hasSetConsentPreferences: typeof window.DG_BANNER_API?.setConsentPreferences === 'function',
                hasDatagrailConsent: typeof window.datagrailConsent !== 'undefined'
            };
            return JSON.stringify(checks, null, 2);
        })();
        """

        webView.evaluateJavaScript(script) { [self] result, error in
            if let error = error {
                logMessages.append("[Test] Error: \(error.localizedDescription)")
            } else if let result = result as? String {
                logMessages.append("[Test] API Status:")
                result.split(separator: "\n").forEach { line in
                    logMessages.append("[Test]   \(line)")
                }
            }
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    @Binding var urlString: String
    @Binding var webView: WKWebView?
    var onLog: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, lastLoadedURL: urlString)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Inject consent preferences before loading
        DataGrailWebViewHelper.injectConsentPreferences(into: configuration)
        onLog("[iOS SDK] Injected consent preferences into WebView configuration")

        // Add message handler to receive console logs from JavaScript
        configuration.userContentController.add(
            context.coordinator,
            name: "consoleLog"
        )

        // Add script to capture console.log
        let consoleScript = """
        (function() {
            const originalLog = console.log;
            console.log = function(...args) {
                window.webkit.messageHandlers.consoleLog.postMessage(args.join(' '));
                originalLog.apply(console, args);
            };
        })();
        """
        let userScript = WKUserScript(
            source: consoleScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Store webView reference for testing (use direct assignment to avoid triggering update)
        if self.webView == nil {
            DispatchQueue.main.async {
                self.webView = webView
            }
        }

        // Load initial URL
        if let url = URL(string: urlString) {
            context.coordinator.lastLoadedURL = urlString
            webView.load(URLRequest(url: url))
        }

        // Listen for consent changes and update the WebView
        DataGrailConsent.shared.onConsentChanged { _ in
            onLog("[iOS SDK] Consent changed, updating WebView...")
            DataGrailWebViewHelper.updateConsentPreferences(in: webView) { success in
                onLog("[iOS SDK] WebView update \(success ? "succeeded" : "failed")")
            }
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only load if the URL binding changed AND it's different from what we last loaded
        guard urlString != context.coordinator.lastLoadedURL else {
            return
        }

        if let url = URL(string: urlString) {
            context.coordinator.lastLoadedURL = urlString
            webView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebViewContainer
        var lastLoadedURL: String
        weak var webView: WKWebView?

        init(parent: WebViewContainer, lastLoadedURL: String) {
            self.parent = parent
            self.lastLoadedURL = lastLoadedURL
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            parent.onLog("[WebView] Page loaded: \(webView.url?.absoluteString ?? "unknown")")

            // Automatically check if consent preferences were injected
            checkInjectedConsent(webView: webView)
        }

        private func checkInjectedConsent(webView: WKWebView) {
            let script = """
            (function() {
                if (window.datagrailConsent) {
                    return JSON.stringify(window.datagrailConsent, null, 2);
                } else {
                    return "window.datagrailConsent is undefined";
                }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    self.parent.onLog("[Auto-Check] Error: \(error.localizedDescription)")
                } else if let result = result as? String {
                    self.parent.onLog("[Auto-Check] Consent preferences injected:")
                    result.split(separator: "\n").forEach { line in
                        self.parent.onLog("[Auto-Check]   \(line)")
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onLog("[WebView] Load failed: \(error.localizedDescription)")
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "consoleLog", let body = message.body as? String {
                parent.onLog("[JS] \(body)")
            }
        }
    }
}

#Preview {
    NavigationView {
        WebViewDemoView()
    }
}
