#if canImport(UIKit)
    import UIKit

    /// Display style for the consent banner
    public enum BannerDisplayStyle {
        /// Modal style with rounded corners, centered on screen (90% height)
        case modal
        /// Full screen style that covers the entire screen
        case fullScreen
    }

    // swiftlint:disable type_body_length
    /// View controller for displaying consent banner with multiple layers
    public class BannerViewController: UIViewController {
        // MARK: - Properties

        private let config: ConsentConfig
        private var currentLayerKey: String
        private var preferences: ConsentPreferences
        private let completion: (ConsentPreferences?) -> Void
        private let displayStyle: BannerDisplayStyle

        private let containerView = UIView()
        private let scrollView = UIScrollView()
        private let contentStackView = UIStackView()
        private let closeButton = UIButton(type: .system)

        // MARK: - Initialization

        public init(
            config: ConsentConfig,
            initialPreferences: ConsentPreferences?,
            displayStyle: BannerDisplayStyle = .modal,
            completion: @escaping (ConsentPreferences?) -> Void
        ) {
            self.config = config
            self.displayStyle = displayStyle
            currentLayerKey = config.layout.firstLayerId

            // Build default preferences from initialCategories
            let allCategoryKeys = Self.getAllCategoryKeys(config)
            preferences =
                initialPreferences
                    ?? ConsentPreferences(
                        isCustomised: false,
                        cookieOptions: allCategoryKeys.map { gtmKey in
                            CategoryConsent(
                                gtmKey: gtmKey,
                                isEnabled: true // Default to enabled
                            )
                        }
                    )
            self.completion = completion

            super.init(nibName: nil, bundle: nil)

            modalPresentationStyle = .overFullScreen
            modalTransitionStyle = .crossDissolve
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Get all category GTM keys from config
        /// Combines initialCategories.initial with any categories found in consent layers
        private static func getAllCategoryKeys(_ config: ConsentConfig) -> [String] {
            var categories = Set<String>()

            // Add categories from initialCategories
            categories.formUnion(config.initialCategories.initial)

            // Also scan consent layers for any additional categories
            for layer in config.layout.consentLayers.values {
                for element in layer.elements {
                    if let layerCategories = element.consentLayerCategories {
                        for category in layerCategories {
                            categories.insert(category.gtmKey)
                        }
                    }
                }
            }

            return Array(categories)
        }

        /// Normalize element type by removing ConsentLayer prefix and Element suffix
        private static func normalizeElementType(_ type: String) -> String {
            type.replacingOccurrences(of: "ConsentLayer", with: "")
                .replacingOccurrences(of: "Element", with: "")
                .lowercased()
        }

        /// Get essential (always-on) category GTM keys by looking up alwaysOn in layout categories
        /// Falls back to checking for "essential" in the category name
        private static func getEssentialCategoryKeys(_ config: ConsentConfig) -> Set<String> {
            var essentialKeys = Set<String>()

            // First, scan consent layers for always-on categories
            for layer in config.layout.consentLayers.values {
                for element in layer.elements where normalizeElementType(element.type) == "category" {
                    if let layerCategories = element.consentLayerCategories {
                        for category in layerCategories where category.alwaysOn {
                            essentialKeys.insert(category.gtmKey)
                        }
                    }
                }
            }

            // Also check for categories with "essential" in the name as fallback
            for gtmKey in config.initialCategories.initial
                where gtmKey.lowercased().contains("essential")
            {
                essentialKeys.insert(gtmKey)
            }

            return essentialKeys
        }

        // MARK: - Lifecycle

        override public func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            renderLayer(currentLayerKey)
        }

        // MARK: - UI Setup

        private func setupUI() {
            switch displayStyle {
            case .modal:
                setupModalUI()
            case .fullScreen:
                setupFullScreenUI()
            }
        }

        private func setupModalUI() {
            view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

            // Container view
            containerView.backgroundColor = .systemBackground
            containerView.layer.cornerRadius = 12
            containerView.layer.shadowColor = UIColor.black.cgColor
            containerView.layer.shadowOpacity = 0.2
            containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
            containerView.layer.shadowRadius = 8
            containerView.translatesAutoresizingMaskIntoConstraints = false
            containerView.isAccessibilityElement = false
            containerView.accessibilityLabel = "Consent Banner"
            view.addSubview(containerView)

            // Close button (always shown in modal)
            setupCloseButton()
            containerView.addSubview(closeButton)

            // Scroll view
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(scrollView)

            // Content stack view
            contentStackView.axis = .vertical
            contentStackView.spacing = 16
            contentStackView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(contentStackView)

            // Constraints
            NSLayoutConstraint.activate([
                // Container - 90% height, centered
                containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                containerView.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor, constant: -20
                ),
                containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                containerView.heightAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.9
                ),

                // Close button
                closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
                closeButton.trailingAnchor.constraint(
                    equalTo: containerView.trailingAnchor, constant: -12
                ),
                closeButton.widthAnchor.constraint(equalToConstant: 44),
                closeButton.heightAnchor.constraint(equalToConstant: 44),

                // Scroll view
                scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
                scrollView.leadingAnchor.constraint(
                    equalTo: containerView.leadingAnchor, constant: 20
                ),
                scrollView.trailingAnchor.constraint(
                    equalTo: containerView.trailingAnchor, constant: -20
                ),
                scrollView.bottomAnchor.constraint(
                    equalTo: containerView.bottomAnchor, constant: -20
                ),

                // Content stack
                contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            ])
        }

        // swiftlint:disable:next function_body_length
        private func setupFullScreenUI() {
            view.backgroundColor = .systemBackground

            // Container view (full screen, no rounded corners)
            containerView.backgroundColor = .systemBackground
            containerView.translatesAutoresizingMaskIntoConstraints = false
            containerView.isAccessibilityElement = false
            containerView.accessibilityLabel = "Consent Banner"
            view.addSubview(containerView)

            // Scroll view
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(scrollView)

            // Content stack view
            contentStackView.axis = .vertical
            contentStackView.spacing = 16
            contentStackView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(contentStackView)

            // Check if current layer has show_close_button enabled
            let currentLayer = config.layout.consentLayers[currentLayerKey]
            let showCloseButton = currentLayer?.showCloseButton ?? false

            if showCloseButton {
                setupCloseButton()
                containerView.addSubview(closeButton)

                NSLayoutConstraint.activate([
                    // Container - full screen
                    containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    containerView.bottomAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.bottomAnchor),

                    // Close button
                    closeButton.topAnchor.constraint(
                        equalTo: containerView.topAnchor, constant: 12
                    ),
                    closeButton.trailingAnchor.constraint(
                        equalTo: containerView.trailingAnchor, constant: -12
                    ),
                    closeButton.widthAnchor.constraint(equalToConstant: 44),
                    closeButton.heightAnchor.constraint(equalToConstant: 44),

                    // Scroll view (below close button)
                    scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
                    scrollView.leadingAnchor.constraint(
                        equalTo: containerView.leadingAnchor, constant: 20
                    ),
                    scrollView.trailingAnchor.constraint(
                        equalTo: containerView.trailingAnchor, constant: -20
                    ),
                    scrollView.bottomAnchor.constraint(
                        equalTo: containerView.bottomAnchor, constant: -20
                    ),

                    // Content stack
                    contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                    contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                    contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                    contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                    contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
                ])
            } else {
                // No close button - scroll view starts from top
                NSLayoutConstraint.activate([
                    // Container - full screen
                    containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    containerView.bottomAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.bottomAnchor),

                    // Scroll view (from top)
                    scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
                    scrollView.leadingAnchor.constraint(
                        equalTo: containerView.leadingAnchor, constant: 20
                    ),
                    scrollView.trailingAnchor.constraint(
                        equalTo: containerView.trailingAnchor, constant: -20
                    ),
                    scrollView.bottomAnchor.constraint(
                        equalTo: containerView.bottomAnchor, constant: -20
                    ),

                    // Content stack
                    contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                    contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                    contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                    contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                    contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
                ])
            }
        }

        private func setupCloseButton() {
            closeButton.setTitle("✕", for: .normal)
            closeButton.titleLabel?.font = .systemFont(ofSize: 24)
            closeButton.tintColor = .secondaryLabel
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.accessibilityLabel = "Close consent banner"
            closeButton.accessibilityHint = "Dismiss without saving preferences"
            closeButton.accessibilityTraits = .button
        }

        // MARK: - Layer Rendering

        private func renderLayer(_ layerKey: String) {
            // Clear current content
            contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            guard let layer = config.layout.consentLayers[layerKey] else {
                // Add error message label
                let errorLabel = UILabel()
                errorLabel.text = "Error: Layer '\(layerKey)' not found"
                errorLabel.textColor = .red
                contentStackView.addArrangedSubview(errorLabel)
                return
            }

            // Render each element
            for element in layer.elements {
                if let view = createElementView(element) {
                    contentStackView.addArrangedSubview(view)
                }
            }

            // If no views were added, show an error message
            if contentStackView.arrangedSubviews.isEmpty {
                let errorLabel = UILabel()
                errorLabel.text = "Debug: No views created from \(layer.elements.count) elements"
                errorLabel.textColor = .orange
                errorLabel.numberOfLines = 0
                contentStackView.addArrangedSubview(errorLabel)
            }
        }

        // MARK: - Locale Helper

        /// Get the preferred locale code, defaulting to "en" if not available
        private func getPreferredLocale(from translations: [String: Any]?) -> String {
            guard let translations else { return "en" }

            // Get the device's preferred language (e.g., "en-US" -> "en")
            let deviceLocale =
                Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"

            // Check if device locale is available
            if translations.keys.contains(deviceLocale) {
                return deviceLocale
            }

            // Fall back to English
            if translations.keys.contains("en") {
                return "en"
            }

            // If no English, use first available
            return translations.keys.first ?? "en"
        }

        /// Get translation for preferred locale with fallback
        private func getTranslation<T>(from translations: [String: T]?) -> T? {
            guard let translations else { return nil }

            // Get the device's preferred language
            let deviceLocale =
                Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"

            // Try device locale first, then English, then any available
            return translations[deviceLocale] ?? translations["en"] ?? translations.values.first
        }

        // MARK: - Element Creation

        private func createElementView(_ element: ConsentLayerElement) -> UIView? {
            // Handle both short ("text") and full ("ConsentLayerTextElement") type names
            let normalizedType = element.type
                .replacingOccurrences(of: "ConsentLayer", with: "")
                .replacingOccurrences(of: "Element", with: "")
                .lowercased()

            switch normalizedType {
            case "text":
                return createTextView(element)
            case "button":
                return createButtonView(element)
            case "link":
                return createLinkView(element)
            case "category":
                return createCategoryView(element)
            case "trackingdetails", "tracking_details":
                return createTrackingDetailsView(element)
            case "browsersignalnotice", "browser_signal_notice":
                // GPC/DNT are web browser signals that don't apply to mobile apps
                // Return nil to hide the notice on mobile
                return nil
            default:
                // Create a label showing the unknown type for debugging
                let label = UILabel()
                label.text = "Unknown type: \(element.type)"
                label.textColor = .gray
                label.font = .systemFont(ofSize: 12)
                return label
            }
        }

        private func createTextView(_ element: ConsentLayerElement) -> UIView? {
            // Try both "value" and "text" fields (different config formats)
            guard let translation: ElementTranslation = getTranslation(from: element.translations)
            else {
                return nil
            }

            guard let text = translation.value ?? translation.text else {
                return nil
            }

            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 16)
            label.textColor = .label
            label.isAccessibilityElement = true
            label.accessibilityLabel = text
            label.accessibilityTraits = .staticText
            return label
        }

        // swiftlint:disable:next function_body_length cyclomatic_complexity
        private func createButtonView(_ element: ConsentLayerElement) -> UIView? {
            guard let action = element.buttonAction,
                  let translation: ElementTranslation = getTranslation(from: element.translations),
                  let text = translation.value ?? translation.text
            else {
                return nil
            }

            let button = UIButton(type: .system)
            button.setTitle(text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            button.backgroundColor = .systemBlue
            button.setTitleColor(.white, for: .normal)
            button.layer.cornerRadius = 8
            button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)

            button.accessibilityTraits = .button

            // Map config button_action values to internal action names
            let internalAction: String
            switch action {
            case "accept_all":
                internalAction = "accept_all"
            case "reject_all":
                internalAction = "reject_all"
            case "accept_some":
                internalAction = "save" // "accept_some" saves user's current toggle selections
            case "custom":
                internalAction = "save" // "custom" means save user's choices
            case "dismiss", "close":
                internalAction = "dismiss"
            case "open_layer":
                internalAction = "navigate"
            case "open_url", "openUrl":
                internalAction = "openUrl"
            case "noop":
                internalAction = "dismiss" // noop buttons should still dismiss the banner
            default:
                internalAction = action
            }

            // Store the action type for buttonTapped handler
            button.accessibilityIdentifier = internalAction

            // Set accessibility hints based on action
            switch internalAction {
            case "accept_all":
                button.accessibilityLabel = text
                button.accessibilityHint = "Accept all consent categories"
            case "reject_all":
                button.accessibilityLabel = text
                button.accessibilityHint = "Reject all non-essential categories"
            case "save":
                button.accessibilityLabel = text
                button.accessibilityHint = "Save your consent preferences"
            case "dismiss":
                button.accessibilityLabel = text
                button.accessibilityHint = "Close without saving"
            case "navigate":
                button.accessibilityLabel = text
                button.accessibilityHint = "View more options"
                // Store target layer ID in a custom property
                if let targetLayerId = element.targetConsentLayer {
                    button.accessibilityValue = targetLayerId
                }
            case "openUrl":
                button.accessibilityLabel = text
                button.accessibilityHint = "Open link in browser"
                button.accessibilityTraits = [.button, .link]
                // Store URL in a custom property
                if let translation: ElementTranslation = getTranslation(
                    from: element.translations),
                    let url = translation.url
                {
                    button.accessibilityValue = url
                }
            default:
                button.accessibilityLabel = text
            }

            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)

            // Height constraint
            let heightConstraint = button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            heightConstraint.isActive = true

            return button
        }

        private func createLinkView(_ element: ConsentLayerElement) -> UIView? {
            // Check if this has link items (new format) or direct translations (old format)
            if let links = element.links, !links.isEmpty {
                // New format: multiple link items
                let containerView = UIStackView()
                containerView.axis = .vertical
                containerView.spacing = 8

                for link in links {
                    guard
                        let translation: ElementTranslation = getTranslation(
                            from: link.translations),
                        let text = translation.text ?? translation.value,
                        let urlString = translation.url
                    else {
                        continue
                    }

                    let button = UIButton(type: .system)
                    button.setTitle(text, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: 14)
                    button.contentHorizontalAlignment = .leading
                    button.accessibilityLabel = text
                    button.accessibilityHint = "Opens \(text) in browser"
                    button.accessibilityTraits = [.button, .link]
                    button.accessibilityValue = urlString
                    button.addTarget(self, action: #selector(linkTapped(_:)), for: .touchUpInside)
                    containerView.addArrangedSubview(button)
                }

                return containerView.arrangedSubviews.isEmpty ? nil : containerView
            } else {
                // Old format: direct translations
                guard
                    let translation: ElementTranslation = getTranslation(
                        from: element.translations),
                    let text = translation.text ?? translation.value,
                    let urlString = translation.url
                else {
                    return nil
                }

                let button = UIButton(type: .system)
                button.setTitle(text, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 14)
                button.contentHorizontalAlignment = .leading
                button.accessibilityLabel = text
                button.accessibilityHint = "Opens \(text) in browser"
                button.accessibilityTraits = [.button, .link]
                button.accessibilityValue = urlString
                button.addTarget(self, action: #selector(linkTapped(_:)), for: .touchUpInside)

                return button
            }
        }

        private func createCategoryView(_ element: ConsentLayerElement) -> UIView? {
            guard let categories = element.consentLayerCategories, !categories.isEmpty
            else {
                return nil
            }

            let containerView = UIView()
            let mainStack = UIStackView()
            mainStack.axis = .vertical
            mainStack.spacing = 8
            mainStack.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(mainStack)

            for category in categories {
                // Stack for each category
                let stackView = UIStackView()
                stackView.axis = .horizontal
                stackView.alignment = .center
                stackView.spacing = 12

                // Category label - use locale fallback
                let label = UILabel()
                let catTranslation: CategoryTranslation? = getTranslation(
                    from: category.translations)
                label.text = catTranslation?.name ?? "Category"
                label.font = .systemFont(ofSize: 16, weight: .medium)
                label.textColor = .label
                label.numberOfLines = 0

                // Toggle switch
                let toggle = UISwitch()
                let isEnabled =
                    preferences.cookieOptions.first(where: {
                        $0.gtmKey == category.gtmKey
                    })?.isEnabled ?? !category.alwaysOn
                toggle.isOn = isEnabled
                toggle.isEnabled = !category.alwaysOn
                toggle.accessibilityIdentifier = category.gtmKey
                toggle.accessibilityLabel =
                    "\(catTranslation?.name ?? "Category") consent"
                toggle.accessibilityValue = isEnabled ? "Enabled" : "Disabled"
                if category.alwaysOn {
                    toggle.accessibilityHint = "Always enabled"
                } else {
                    toggle.accessibilityHint = "Double tap to toggle"
                }
                toggle.addTarget(self, action: #selector(categoryToggled(_:)), for: .valueChanged)

                stackView.addArrangedSubview(label)
                stackView.addArrangedSubview(toggle)
                mainStack.addArrangedSubview(stackView)
            }

            // Constraints
            NSLayoutConstraint.activate([
                mainStack.topAnchor.constraint(equalTo: containerView.topAnchor),
                mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])

            return containerView
        }

        private func createTrackingDetailsView(_ element: ConsentLayerElement) -> UIView? {
            // Standalone tracking details element - shows tracking services/cookies
            let containerView = UIStackView()
            containerView.axis = .vertical
            containerView.spacing = 12

            // If this element has a title
            if let translation: ElementTranslation = getTranslation(from: element.translations),
               let text = translation.value ?? translation.text
            {
                let label = UILabel()
                label.text = text
                label.numberOfLines = 0
                label.font = .systemFont(ofSize: 14)
                label.textColor = .secondaryLabel
                containerView.addArrangedSubview(label)
            }

            // Note: Full tracking details would need to fetch service-metadata.json
            // For now, just show a placeholder

            return containerView.arrangedSubviews.isEmpty ? nil : containerView
        }

        private func createBrowserSignalNoticeView(_ element: ConsentLayerElement) -> UIView? {
            // Get the notice text for the current locale with fallback
            guard
                let translation: BrowserSignalNoticeTranslation = getTranslation(
                    from: element.browserSignalNoticeTranslations),
                let text = translation.value
            else {
                return nil
            }

            let containerView = UIStackView()
            containerView.axis = .horizontal
            containerView.spacing = 8
            containerView.alignment = .top

            // Optional icon
            if element.showIcon == true {
                let iconLabel = UILabel()
                iconLabel.text = "⚠️"
                iconLabel.font = .systemFont(ofSize: 16)
                containerView.addArrangedSubview(iconLabel)
            }

            // Notice text
            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 14)
            label.textColor = .label
            label.isAccessibilityElement = true
            label.accessibilityLabel = text
            containerView.addArrangedSubview(label)

            return containerView
        }

        // MARK: - Actions

        @objc private func buttonTapped(_ sender: UIButton) {
            guard let action = sender.accessibilityIdentifier else { return }

            switch action {
            case "accept_all":
                handleAcceptAll()
            case "reject_all":
                handleRejectAll()
            case "save":
                handleSavePreferences()
            case "dismiss":
                handleDismiss()
            case "navigate":
                if let targetLayerId = sender.accessibilityValue {
                    navigateToLayer(targetLayerId)
                }
            case "openUrl":
                if let urlString = sender.accessibilityValue, let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
            default:
                break
            }
        }

        @objc private func linkTapped(_ sender: UIButton) {
            guard let urlString = sender.accessibilityValue,
                  let url = URL(string: urlString)
            else {
                return
            }
            UIApplication.shared.open(url)
        }

        @objc private func categoryToggled(_ sender: UISwitch) {
            guard let gtmKey = sender.accessibilityIdentifier else { return }

            // Update preferences
            if let index = preferences.cookieOptions.firstIndex(where: { $0.gtmKey == gtmKey }) {
                preferences.cookieOptions[index].isEnabled = sender.isOn
            } else {
                preferences.cookieOptions.append(
                    CategoryConsent(gtmKey: gtmKey, isEnabled: sender.isOn))
            }
            preferences.isCustomised = true
        }

        @objc private func trackingDetailsTapped(_ sender: UIButton) {
            guard let gtmKey = sender.accessibilityIdentifier else {
                return
            }

            // Find the category across all layers
            var categoryInfo: ConsentLayerCategory?
            for layer in config.layout.consentLayers.values {
                for element in layer.elements
                    where element.type == "category" || element.type == "tracking_details"
                {
                    if let categories = element.consentLayerCategories {
                        categoryInfo = categories.first(where: { $0.gtmKey == gtmKey })
                        if categoryInfo != nil { break }
                    }
                }
                if categoryInfo != nil { break }
            }

            guard let category = categoryInfo else { return }

            // Create alert with tracking technologies (cookies/patterns)
            let message =
                category.cookiePatterns.isEmpty
                    ? "No tracking technologies"
                    : category.cookiePatterns.joined(separator: "\n")
            let alert = UIAlertController(
                title: "Tracking Technologies",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }

        @objc private func closeTapped() {
            handleDismiss()
        }

        // MARK: - Handlers

        private func handleAcceptAll() {
            preferences.isCustomised = false
            let allCategories = Self.getAllCategoryKeys(config)
            preferences.cookieOptions = allCategories.map { gtmKey in
                CategoryConsent(gtmKey: gtmKey, isEnabled: true)
            }
            completion(preferences)
            dismiss(animated: true)
        }

        private func handleRejectAll() {
            preferences.isCustomised = false
            let allCategories = Self.getAllCategoryKeys(config)
            let essentialCategories = Self.getEssentialCategoryKeys(config)
            preferences.cookieOptions = allCategories.map { gtmKey in
                CategoryConsent(gtmKey: gtmKey, isEnabled: essentialCategories.contains(gtmKey))
            }
            completion(preferences)
            dismiss(animated: true)
        }

        private func handleSavePreferences() {
            completion(preferences)
            dismiss(animated: true)
        }

        private func handleDismiss() {
            completion(nil)
            dismiss(animated: true)
        }

        private func navigateToLayer(_ layerKey: String) {
            currentLayerKey = layerKey
            UIView.transition(
                with: contentStackView, duration: 0.3, options: .transitionCrossDissolve
            ) {
                self.renderLayer(layerKey)
            }
        }
    }
    // swiftlint:enable type_body_length
#endif
