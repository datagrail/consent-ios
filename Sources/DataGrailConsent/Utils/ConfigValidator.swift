import Foundation

/// Validates consent configuration structure
public enum ConfigValidator {
    /// Validate a consent configuration
    /// - Parameter config: The configuration to validate
    /// - Throws: ConsentError.validationError if validation fails
    public static func validate(_ config: ConsentConfig) throws {
        // Validate required fields
        try validateRequiredFields(config)

        // Validate layers
        try validateLayers(config)

        // Validate elements
        try validateElements(config)

        // Validate categories
        try validateCategories(config)
    }

    private static func validateRequiredFields(_ config: ConsentConfig) throws {
        guard !config.version.isEmpty else {
            throw ConsentError.validationError("Missing required field: version")
        }

        guard !config.dgCustomerId.isEmpty else {
            throw ConsentError.validationError("Missing required field: dgCustomerId")
        }

        guard !config.privacyDomain.isEmpty else {
            throw ConsentError.validationError("Missing required field: privacyDomain")
        }

        guard ["optin", "optout"].contains(config.consentMode) else {
            throw ConsentError.validationError("Invalid consentMode: \(config.consentMode)")
        }
    }

    private static func validateLayers(_ config: ConsentConfig) throws {
        guard !config.layout.consentLayers.isEmpty else {
            throw ConsentError.validationError("No consent layers defined")
        }

        guard config.layout.consentLayers[config.layout.firstLayerId] != nil else {
            throw ConsentError.validationError(
                "firstLayerId '\(config.layout.firstLayerId)' does not reference an existing layer"
            )
        }

        // Validate that all layers have at least one element
        for (layerId, layer) in config.layout.consentLayers {
            guard !layer.elements.isEmpty else {
                throw ConsentError.validationError("Layer '\(layerId)' has no elements")
            }
        }
    }

    private static func validateElements(_ config: ConsentConfig) throws {
        let validElementTypes = [
            "ConsentLayerTextElement",
            "ConsentLayerButtonElement",
            "ConsentLayerLinkElement",
            "ConsentLayerCategoryElement",
            "ConsentLayerTrackingDetailsElement",
            "ConsentLayerBrowserSignalNoticeElement",
        ]

        for layer in config.layout.consentLayers.values {
            for element in layer.elements {
                // Validate element type
                guard validElementTypes.contains(element.type) else {
                    throw ConsentError.validationError("Invalid element type: \(element.type)")
                }

                // Validate button actions that reference layers
                if element.buttonAction == "open_layer" {
                    if let targetId = element.targetConsentLayer {
                        guard config.layout.consentLayers[targetId] != nil else {
                            throw ConsentError.validationError(
                                "Button target layer '\(targetId)' does not exist"
                            )
                        }
                    } else {
                        throw ConsentError.validationError(
                            "Button with action 'open_layer' must specify targetConsentLayer"
                        )
                    }
                }

                // Validate translations exist
                if element.type != "ConsentLayerCategoryElement" {
                    guard let translations = element.translations, !translations.isEmpty else {
                        throw ConsentError.validationError("Element '\(element.id)' has no translations")
                    }
                }
            }
        }
    }

    private static func validateCategories(_ config: ConsentConfig) throws {
        let validPrimitives = [
            "dg-category-essential",
            "dg-category-performance",
            "dg-category-functional",
            "dg-category-marketing",
        ]

        // Find all category elements
        let categoryElements = config.layout.consentLayers.values
            .flatMap(\.elements)
            .filter { $0.type == "ConsentLayerCategoryElement" }

        for element in categoryElements {
            guard let categories = element.consentLayerCategories, !categories.isEmpty else {
                throw ConsentError.validationError("Category element '\(element.id)' has no categories")
            }

            for category in categories {
                // Validate primitive
                guard validPrimitives.contains(category.primitive) else {
                    throw ConsentError.validationError("Invalid category primitive: \(category.primitive)")
                }

                // Validate gtmKey
                guard !category.gtmKey.isEmpty else {
                    throw ConsentError.validationError("Category '\(category.id)' has empty gtmKey")
                }

                // Validate translations
                guard !category.translations.isEmpty else {
                    throw ConsentError.validationError("Category '\(category.id)' has no translations")
                }
            }
        }
    }
}
