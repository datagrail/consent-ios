# DataGrail Consent iOS SDK

Native iOS SDK for displaying consent banners and managing user privacy preferences.

## Installation

### CocoaPods (Recommended)

CocoaPods is the recommended installation method. Add the DataGrail pod source and dependency to your `Podfile`:

```ruby
source 'https://github.com/datagrail/podspecs.git'
source 'https://cdn.cocoapods.org/'

target 'YourApp' do
  use_frameworks!
  pod 'DataGrailConsent', '~> 1.0'
end
```

Then run:

```bash
pod install
```

Open the generated `.xcworkspace` file (not `.xcodeproj`) going forward.

### Swift Package Manager

If you prefer SPM, add the package in Xcode:

1. File > Add Packages
2. Enter: `https://github.com/datagrail/consent-banner.git`
3. Select version `1.0.0` or higher

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/datagrail/consent-banner.git", from: "1.0.0")
]
```

## Quick Start

```swift
import DataGrailConsent

// In AppDelegate or SceneDelegate
DataGrailConsent.shared.initialize(
    configUrl: "https://consent.datagrail.io/config/YOUR_CONFIG.json"
) { result in
    switch result {
    case .success:
        // Check if user needs to consent
        if DataGrailConsent.shared.needsConsent() {
            // Show your consent UI
        }
    case .failure(let error):
        print("Failed to initialize: \(error)")
    }
}

// Listen for changes
DataGrailConsent.shared.onConsentChanged { preferences in
    // Update your tracking configuration
    updateTracking(preferences)
}

// Check consent status
if DataGrailConsent.shared.isCategoryEnabled("category_marketing") {
    // Marketing category enabled
    enableMarketingTracking()
}
```

## Requirements

**Runtime:**

- iOS 13.0+
- Swift 5.7+

**Development:**

- Xcode 14+
- SwiftLint 0.56.2+ (for linting)

  ```bash
  brew install swiftlint
  ```

- pre-commit (for git hooks)

  ```bash
  brew install pre-commit
  cd /path/to/consent-banner
  pre-commit install
  ```

## API Documentation

See [main README](../README.md#api-reference) for full API documentation.

### Key Methods

- `initialize(configUrl:completion:)` - Initialize SDK with config URL
- `needsConsent() -> Bool` - Check if user needs to provide consent
- `getUserPreferences() -> ConsentPreferences?` - Get user's saved preferences
- `getCategories() -> ConsentPreferences?` - Get categories with current consent state
- `savePreferences(_:completion:)` - Save user preferences
- `acceptAll(completion:)` - Accept all categories
- `rejectAll(completion:)` - Reject all non-essential categories
- `isCategoryEnabled(_:) -> Bool` - Check specific category
- `onConsentChanged(_:)` - Listen for consent changes
- `reset()` - Clear all stored data

## Example Usage

### Save Preferences

```swift
let preferences = ConsentPreferences(
    isCustomised: true,
    cookieOptions: [
        CategoryConsent(gtmKey: "category_marketing", isEnabled: true),
        CategoryConsent(gtmKey: "category_analytics", isEnabled: false),
        CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true)
    ]
)

DataGrailConsent.shared.savePreferences(preferences) { result in
    switch result {
    case .success:
        print("Preferences saved")
    case .failure(let error):
        print("Failed to save: \(error)")
    }
}
```

### Accept All

```swift
DataGrailConsent.shared.acceptAll { result in
    // All categories enabled and saved
}
```

### Check Category Status

```swift
if DataGrailConsent.shared.isCategoryEnabled("category_marketing") {
    // Marketing category is enabled
    enableMarketingTracking()
}
```

## Testing

```bash
swift test
```

**Status:** ✅ 14/14 tests passing

## Architecture

The SDK uses a callback-based API for iOS 13+ compatibility:

- **Models**: `ConsentConfig`, `ConsentPreferences`, `CategoryConsent`
- **Storage**: `ConsentStorage` using UserDefaults
- **Network**: `NetworkClient` with retry logic
- **Services**: `ConfigService`, `ConsentService`
- **Manager**: `ConsentManager` orchestrates all layers
- **Public API**: `DataGrailConsent` singleton

## UI Implementation

**Status:** UI components currently under reconstruction. Core functionality (initialization, preference management, backend sync) is complete and tested.

## License

Apache 2.0
