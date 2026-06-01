#if os(tvOS)
    import UIKit

    /// View controller for displaying consent banner on tvOS with focus engine support
    /// All elements designed for 10-foot viewing distance and D-pad/Siri Remote navigation
    public class BannerViewControllerTvOS: UIViewController {
        // MARK: - Properties

        private let config: ConsentConfig
        private var currentLayerKey: String
        private var preferences: ConsentPreferences
        private let completion: (ConsentPreferences?) -> Void
        private var layerHistory: [String] = []

        private let scrollView = UIScrollView()
        private let contentStackView = UIStackView()

        // QR pairing support
        private let qrImage: UIImage?
        private let pairingCoordinator: PairingCoordinator?
        private var qrContainerView: UIView?

        // MARK: - Initialization

        public init(
            config: ConsentConfig,
            initialPreferences: ConsentPreferences?,
            qrImage: UIImage? = nil,
            pairingCoordinator: PairingCoordinator? = nil,
            completion: @escaping (ConsentPreferences?) -> Void
        ) {
            self.qrImage = qrImage
            self.pairingCoordinator = pairingCoordinator
            self.config = config
            self.currentLayerKey = config.layout.firstLayerId

            // Build default preferences from initialCategories
            let allCategoryKeys = Self.getAllCategoryKeys(config)
            self.preferences =
                initialPreferences
                ?? ConsentPreferences(
                    isCustomised: false,
                    cookieOptions: allCategoryKeys.map { gtmKey in
                        CategoryConsent(
                            gtmKey: gtmKey,
                            isEnabled: true  // Default to enabled
                        )
                    }
                )

            self.completion = completion
            super.init(nibName: nil, bundle: nil)

            // Full screen presentation
            modalPresentationStyle = .fullScreen
            modalTransitionStyle = .crossDissolve
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - Lifecycle

        public override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            renderLayer(currentLayerKey)
        }

        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Set initial focus
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }

        // MARK: - Setup

        private func setupUI() {
            view.backgroundColor = UIColor.black.withAlphaComponent(0.9)

            // ScrollView for content
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.showsVerticalScrollIndicator = true
            scrollView.alwaysBounceVertical = true
            scrollView.remembersLastFocusedIndexPath = true
            view.addSubview(scrollView)

            // Content stack view
            contentStackView.axis = .vertical
            contentStackView.spacing = 24
            contentStackView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(contentStackView)

            // Layout
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60
                ),
                scrollView.leadingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 90
                ),
                scrollView.trailingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -90
                ),
                scrollView.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60
                ),

                contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            ])
        }

        // MARK: - Menu Button (Back/Dismiss)

        public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard press.type == .menu else { continue }
                handled = true

                if layerHistory.isEmpty {
                    // On first layer: dismiss without saving
                    completion(nil)
                    dismiss(animated: true)
                } else {
                    // Navigate back to previous layer
                    let previousLayer = layerHistory.removeLast()
                    currentLayerKey = previousLayer
                    renderLayer(currentLayerKey)
                }
            }

            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }

        // MARK: - Layer Rendering

        private func renderLayer(_ layerKey: String) {
            // Clear current content
            contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            guard let layer = config.layout.consentLayers[layerKey] else {
                let errorLabel = UILabel()
                errorLabel.text = "Error: Layer '\(layerKey)' not found"
                errorLabel.textColor = .red
                errorLabel.font = .systemFont(ofSize: 29)
                contentStackView.addArrangedSubview(errorLabel)
                return
            }

            // If on first layer and QR is available, show QR code at the top
            let isFirstLayer = layerKey == config.layout.firstLayerId
            if isFirstLayer, let qrImage = qrImage, pairingCoordinator != nil {
                let qrView = createQRView(qrImage: qrImage)
                qrContainerView = qrView
                contentStackView.addArrangedSubview(qrView)
            } else {
                qrContainerView = nil
            }

            // Render each element
            for element in layer.elements {
                if let view = createElementView(element) {
                    contentStackView.addArrangedSubview(view)
                }
            }

            // Update focus after layer transition
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }

        private func createQRView(qrImage: UIImage) -> UIView {
            let container = UIView()
            container.backgroundColor = UIColor.secondarySystemBackground
            container.layer.cornerRadius = 16

            let imageView = UIImageView(image: qrImage)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)

            let label = UILabel()
            label.text = "Scan with your phone to manage privacy settings"
            label.font = .systemFont(ofSize: 29)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
                imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 300),
                imageView.heightAnchor.constraint(equalToConstant: 300),

                label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -40),
            ])

            return container
        }

        /// Remove QR code view (called on timeout)
        public func removeQRCode() {
            if let qrView = qrContainerView {
                qrView.removeFromSuperview()
                qrContainerView = nil
                setNeedsFocusUpdate()
                updateFocusIfNeeded()
            }
        }

        // MARK: - Locale Helper

        private func getTranslation<T>(from translations: [String: T]?) -> T? {
            guard let translations else { return nil }
            let deviceLocale =
                Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"
            return translations[deviceLocale] ?? translations["en"] ?? translations.values.first
        }

        // MARK: - Element Creation

        private func createElementView(_ element: ConsentLayerElement) -> UIView? {
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
            case "browsersignalnotice", "browser_signal_notice",
                "languagepicker", "language_picker":
                // Not applicable to tvOS
                return nil
            default:
                return nil
            }
        }

        private func createTextView(_ element: ConsentLayerElement) -> UIView? {
            guard let translation: ElementTranslation = getTranslation(from: element.translations),
                let text = translation.value ?? translation.text
            else {
                return nil
            }

            let label = UILabel()
            label.numberOfLines = 0

            // Determine font size based on style
            let fontSize: CGFloat
            let fontWeight: UIFont.Weight
            if let style = element.style?.lowercased() {
                if style.contains("heading") || style.contains("title") {
                    fontSize = 38  // tvOS heading minimum
                    fontWeight = .bold
                } else {
                    fontSize = 29  // tvOS body minimum
                    fontWeight = .regular
                }
            } else {
                fontSize = 29
                fontWeight = .regular
            }

            let font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
            let color = UIColor.label
            renderRichText(text, in: label, font: font, color: color)

            label.isAccessibilityElement = true
            if let attrText = label.attributedText {
                label.accessibilityLabel = attrText.string
            } else {
                label.accessibilityLabel = label.text ?? text
            }
            label.accessibilityTraits = .staticText

            return label
        }

        private func renderRichText(_ text: String, in label: UILabel, font: UIFont, color: UIColor) {
            let containsHtml = text.range(of: "<[a-zA-Z][^>]*>", options: .regularExpression) != nil
            guard containsHtml,
                let data = text.data(using: .utf8),
                let attr = try? NSMutableAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue,
                    ],
                    documentAttributes: nil
                )
            else {
                label.text = containsHtml
                    ? text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    : text
                label.font = font
                label.textColor = color
                return
            }

            let fullRange = NSRange(location: 0, length: attr.length)
            attr.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                if let existingFont = value as? UIFont {
                    let traits = existingFont.fontDescriptor.symbolicTraits
                    var descriptor = font.fontDescriptor
                    if let traitDescriptor = descriptor.withSymbolicTraits(traits) {
                        descriptor = traitDescriptor
                    }
                    attr.addAttribute(
                        .font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: range
                    )
                } else {
                    attr.addAttribute(.font, value: font, range: range)
                }
            }
            attr.addAttribute(.foregroundColor, value: color, range: fullRange)
            label.attributedText = attr
        }

        // swiftlint:disable:next cyclomatic_complexity function_body_length
        private func createButtonView(_ element: ConsentLayerElement) -> UIView? {
            guard let action = element.buttonAction,
                let translation: ElementTranslation = getTranslation(from: element.translations),
                let text = translation.value ?? translation.text
            else {
                return nil
            }

            let button = UIButton(type: .system)
            button.setTitle(text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 31, weight: .semibold)
            button.backgroundColor = .systemBlue
            button.setTitleColor(.white, for: .normal)
            button.layer.cornerRadius = 12
            button.contentEdgeInsets = UIEdgeInsets(top: 20, left: 40, bottom: 20, right: 40)

            // Map config button_action values
            let internalAction: String
            switch action {
            case "accept_all":
                internalAction = "accept_all"
            case "reject_all":
                internalAction = "reject_all"
            case "accept_some", "custom":
                internalAction = "save"
            case "dismiss", "close", "noop":
                internalAction = "dismiss"
            case "open_layer":
                internalAction = "navigate"
            case "open_url", "openUrl":
                internalAction = "openUrl"
            default:
                internalAction = action
            }

            button.accessibilityIdentifier = internalAction
            button.accessibilityTraits = .button

            // Store target layer or URL
            if internalAction == "navigate", let targetLayerId = element.targetConsentLayer {
                button.accessibilityValue = targetLayerId
            } else if internalAction == "openUrl",
                let translation: ElementTranslation = getTranslation(from: element.translations),
                let url = translation.url
            {
                button.accessibilityValue = url
            }

            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .primaryActionTriggered)

            // Height constraint — tvOS buttons minimum 66pt
            let heightConstraint = button.heightAnchor.constraint(greaterThanOrEqualToConstant: 66)
            heightConstraint.isActive = true

            return button
        }

        private func createLinkView(_ element: ConsentLayerElement) -> UIView? {
            if let links = element.links, !links.isEmpty {
                let containerView = UIStackView()
                containerView.axis = .vertical
                containerView.spacing = 16

                for linkItem in links {
                    guard let translation: LinkTranslation = getTranslation(
                        from: linkItem.translations
                    ),
                        let text = translation.value ?? translation.text,
                        let urlString = translation.url
                    else {
                        continue
                    }

                    let button = UIButton(type: .system)
                    button.setTitle(text, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: 29)
                    button.setTitleColor(.systemBlue, for: .normal)
                    button.contentHorizontalAlignment = .leading
                    button.accessibilityIdentifier = "openUrl"
                    button.accessibilityValue = urlString
                    button.accessibilityTraits = [.button, .link]
                    button.addTarget(
                        self, action: #selector(buttonTapped(_:)), for: .primaryActionTriggered
                    )
                    containerView.addArrangedSubview(button)
                }

                return containerView.arrangedSubviews.isEmpty ? nil : containerView
            }

            // Old format: single link
            guard let translation: ElementTranslation = getTranslation(from: element.translations),
                let text = translation.value ?? translation.text,
                let urlString = translation.url
            else {
                return nil
            }

            let button = UIButton(type: .system)
            button.setTitle(text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 29)
            button.setTitleColor(.systemBlue, for: .normal)
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "openUrl"
            button.accessibilityValue = urlString
            button.accessibilityTraits = [.button, .link]
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .primaryActionTriggered)

            return button
        }

        private func createCategoryView(_ element: ConsentLayerElement) -> UIView? {
            guard let categories = element.consentLayerCategories, !categories.isEmpty else {
                return nil
            }

            let containerView = UIStackView()
            containerView.axis = .vertical
            containerView.spacing = 20

            // Get essential categories (always on)
            let essentialKeys = config.initialCategories.initial

            for category in categories {
                let gtmKey = category.gtmKey
                let isEssential = essentialKeys.contains(gtmKey)
                let isEnabled = preferences.cookieOptions.first(where: { $0.gtmKey == gtmKey })?
                    .isEnabled ?? true

                // Get category name
                guard let translation: CategoryTranslation = getTranslation(
                    from: category.translations
                ),
                    let categoryName = translation.name
                else {
                    continue
                }

                // Create focusable toggle row
                let toggleRow = CategoryToggleRow(
                    gtmKey: gtmKey,
                    name: categoryName,
                    isEnabled: isEnabled,
                    isEssential: isEssential
                )
                toggleRow.onToggle = { [weak self] newValue in
                    self?.updateCategoryConsent(gtmKey: gtmKey, isEnabled: newValue)
                }

                containerView.addArrangedSubview(toggleRow)
            }

            // Optional tracking details link
            if element.showTrackingDetailsLink == true,
                let trackingDetailsTranslation: TrackingDetailsLinkTranslation = getTranslation(
                    from: element.trackingDetailsLinkTranslations
                ),
                let linkText = trackingDetailsTranslation.value ?? trackingDetailsTranslation.text,
                let url = config.trackingDetailsUrl.isEmpty ? nil : config.trackingDetailsUrl
            {
                let linkButton = UIButton(type: .system)
                linkButton.setTitle(linkText, for: .normal)
                linkButton.titleLabel?.font = .systemFont(ofSize: 29)
                linkButton.setTitleColor(.systemBlue, for: .normal)
                linkButton.contentHorizontalAlignment = .leading
                linkButton.accessibilityIdentifier = "openUrl"
                linkButton.accessibilityValue = url
                linkButton.accessibilityTraits = [.button, .link]
                linkButton.addTarget(
                    self, action: #selector(buttonTapped(_:)), for: .primaryActionTriggered
                )

                containerView.addArrangedSubview(linkButton)
            }

            return containerView
        }

        private func createTrackingDetailsView(_ element: ConsentLayerElement) -> UIView? {
            // Tracking details is a complex web-only component showing vendor/cookie lists
            // For tvOS we show a simplified "View details online" message
            guard let translation: ElementTranslation = getTranslation(from: element.translations),
                let text = translation.value ?? translation.text
            else {
                return nil
            }

            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 29)
            label.textColor = .secondaryLabel
            return label
        }

        // MARK: - Actions

        @objc private func buttonTapped(_ sender: UIButton) {
            guard let action = sender.accessibilityIdentifier else { return }

            switch action {
            case "accept_all":
                acceptAll()
            case "reject_all":
                rejectAll()
            case "save":
                savePreferences()
            case "dismiss":
                completion(nil)
                dismiss(animated: true)
            case "navigate":
                if let targetLayerId = sender.accessibilityValue {
                    navigateToLayer(targetLayerId)
                }
            case "openUrl":
                if let urlString = sender.accessibilityValue, let url = URL(string: urlString) {
                    openURL(url)
                }
            default:
                break
            }
        }

        private func acceptAll() {
            // Enable all categories
            preferences = ConsentPreferences(
                isCustomised: true,
                cookieOptions: preferences.cookieOptions.map {
                    CategoryConsent(gtmKey: $0.gtmKey, isEnabled: true)
                }
            )
            completion(preferences)
            dismiss(animated: true)
        }

        private func rejectAll() {
            // Only enable essential categories
            let essentialKeys = config.initialCategories.initial
            preferences = ConsentPreferences(
                isCustomised: true,
                cookieOptions: preferences.cookieOptions.map {
                    CategoryConsent(gtmKey: $0.gtmKey, isEnabled: essentialKeys.contains($0.gtmKey))
                }
            )
            completion(preferences)
            dismiss(animated: true)
        }

        private func savePreferences() {
            preferences.isCustomised = true
            completion(preferences)
            dismiss(animated: true)
        }

        private func navigateToLayer(_ layerKey: String) {
            // Save current layer to history
            layerHistory.append(currentLayerKey)
            currentLayerKey = layerKey
            renderLayer(layerKey)
        }

        private func openURL(_ url: URL) {
            UIApplication.shared.open(url)
        }

        private func updateCategoryConsent(gtmKey: String, isEnabled: Bool) {
            if let index = preferences.cookieOptions.firstIndex(where: { $0.gtmKey == gtmKey }) {
                preferences.cookieOptions[index] = CategoryConsent(
                    gtmKey: gtmKey, isEnabled: isEnabled
                )
            }
        }

        // MARK: - Focus

        public override var preferredFocusEnvironments: [UIFocusEnvironment] {
            // Focus the first focusable element in the content
            for subview in contentStackView.arrangedSubviews {
                if subview.canBecomeFocused {
                    return [subview]
                }
                // Check children (e.g., buttons in stack views)
                if let stackView = subview as? UIStackView {
                    for child in stackView.arrangedSubviews where child.canBecomeFocused {
                        return [child]
                    }
                }
            }
            return [scrollView]
        }

        // MARK: - Helper

        private static func getAllCategoryKeys(_ config: ConsentConfig) -> [String] {
            var keys: Set<String> = []
            for layer in config.layout.consentLayers.values {
                for element in layer.elements where element.type.lowercased().contains("category") {
                    if let categories = element.consentLayerCategories {
                        for category in categories {
                            keys.insert(category.gtmKey)
                        }
                    }
                }
            }
            return Array(keys).sorted()
        }
    }

    // MARK: - Custom Toggle Row for tvOS

    /// Focusable category toggle row for tvOS (custom control for D-pad interaction)
    private class CategoryToggleRow: UIView {
        private let gtmKey: String
        private let nameLabel = UILabel()
        private let stateLabel = UILabel()
        private var isEnabled: Bool
        private let isEssential: Bool

        var onToggle: ((Bool) -> Void)?

        init(gtmKey: String, name: String, isEnabled: Bool, isEssential: Bool) {
            self.gtmKey = gtmKey
            self.isEnabled = isEnabled
            self.isEssential = isEssential
            super.init(frame: .zero)

            backgroundColor = UIColor.secondarySystemBackground
            layer.cornerRadius = 12

            nameLabel.text = name
            nameLabel.font = .systemFont(ofSize: 29)
            nameLabel.textColor = .label
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(nameLabel)

            stateLabel.font = .systemFont(ofSize: 29, weight: .semibold)
            stateLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stateLabel)

            updateStateLabel()

            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
                nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                nameLabel.trailingAnchor.constraint(
                    equalTo: stateLabel.leadingAnchor, constant: -20
                ),

                stateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
                stateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                stateLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

                heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            ])

            // Accessibility
            isAccessibilityElement = true
            accessibilityLabel = name
            accessibilityTraits = isEssential ? [.staticText] : [.button]
            updateAccessibilityValue()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func updateStateLabel() {
            stateLabel.text = isEnabled ? "ON" : "OFF"
            stateLabel.textColor = isEnabled ? .systemGreen : .systemRed
        }

        private func updateAccessibilityValue() {
            if isEssential {
                accessibilityValue = "Always enabled"
            } else {
                accessibilityValue = isEnabled ? "Enabled" : "Disabled"
            }
        }

        // MARK: - Focus

        public override var canBecomeFocused: Bool {
            !isEssential  // Essential categories cannot be toggled
        }

        public override func didUpdateFocus(
            in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator
        ) {
            super.didUpdateFocus(in: context, with: coordinator)

            coordinator.addCoordinatedAnimations({
                if self.isFocused {
                    self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
                    self.layer.shadowColor = UIColor.white.cgColor
                    self.layer.shadowOpacity = 0.8
                    self.layer.shadowRadius = 10
                    self.layer.shadowOffset = .zero
                } else {
                    self.transform = .identity
                    self.layer.shadowOpacity = 0
                }
            }, completion: nil)
        }

        // MARK: - Interaction

        public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false

            for press in presses {
                if press.type == .select || press.type == .playPause {
                    // Select flips the toggle
                    handled = true
                    toggle()
                } else if press.type == .leftArrow {
                    // Left arrow = disable
                    handled = true
                    if isEnabled {
                        toggle()
                    }
                } else if press.type == .rightArrow {
                    // Right arrow = enable
                    handled = true
                    if !isEnabled {
                        toggle()
                    }
                }
            }

            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }

        private func toggle() {
            guard !isEssential else { return }
            isEnabled.toggle()
            updateStateLabel()
            updateAccessibilityValue()
            onToggle?(isEnabled)
        }
    }

#endif
