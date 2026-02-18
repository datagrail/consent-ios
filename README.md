# DataGrail Consent iOS SDK

Native iOS SDK for displaying consent banners and managing user privacy preferences.

## Installation

### CocoaPods (Recommended)

Add the DataGrail pod to your `Podfile`:

```ruby
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

Add the package in Xcode:

1. File > Add Packages
2. Enter: `https://github.com/datagrail/consent-ios.git`
3. Select version `1.0.0` or higher

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/datagrail/consent-ios.git", from: "1.0.0")
]
```

## Quick Start

```swift
import DataGrailConsent

// In AppDelegate or SceneDelegate
let configUrl = URL(string: "https://consent.datagrail.io/config/YOUR_CONFIG.json")!

DataGrailConsent.shared.initialize(configUrl: configUrl) { result in
    switch result {
    case .success:
        // Check if user needs to see the consent banner
        if try DataGrailConsent.shared.shouldDisplayBanner() {
            DataGrailConsent.shared.showBanner(from: viewController) { preferences in
                // User completed the consent flow
            }
        }
    case .failure(let error):
        print("Failed to initialize: \(error)")
    }
}

// Listen for consent changes
DataGrailConsent.shared.onConsentChanged { preferences in
    updateTracking(preferences)
}

// Check consent for a specific category
if try DataGrailConsent.shared.isCategoryEnabled("dg-category-marketing") {
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
  cd /path/to/consent-ios
  pre-commit install
  ```

## API Reference

### Initialization

| Method | Description |
|--------|-------------|
| `DataGrailConsent.shared` | Singleton instance |
| `initialize(configUrl:completion:)` | Initialize the SDK with a remote config URL. `configUrl` is a `URL`. |

### Consent Status

These methods throw `ConsentError.notInitialized` if called before `initialize` completes.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `shouldDisplayBanner()` | `Bool` | Whether the consent banner should be shown |
| `hasUserConsent()` | `Bool` | Whether the user has previously saved preferences |
| `getUserPreferences()` | `ConsentPreferences?` | The user's saved preferences, if any |
| `getCategories()` | `ConsentPreferences?` | Effective categories (saved preferences or config defaults) |
| `isCategoryEnabled(_:)` | `Bool` | Whether a specific category is enabled |
| `getConfig()` | `ConsentConfig?` | The loaded configuration (does not throw) |

### Consent Management

| Method | Description |
|--------|-------------|
| `savePreferences(_:completion:)` | Save user preferences and sync to backend |
| `acceptAll(completion:)` | Accept all consent categories |
| `rejectAll(completion:)` | Reject all non-essential categories |
| `reset()` | Clear all stored consent data |

### Banner Display

| Method | Description |
|--------|-------------|
| `showBanner(from:completion:)` | Present the consent banner modally from a view controller |
| `showBanner(from:style:completion:)` | Present with a specific `BannerDisplayStyle` |

`BannerDisplayStyle` options:
- `.modal` — 90% height sheet with rounded corners (default)
- `.fullScreen` — Full screen presentation

### Event Tracking & Callbacks

| Method | Description |
|--------|-------------|
| `trackBannerShown(completion:)` | Record a banner impression event |
| `onConsentChanged(_:)` | Register a callback invoked whenever preferences change |

### Offline Support

| Method | Description |
|--------|-------------|
| `retryPendingRequests(completion:)` | Retry any queued requests that failed while offline. Completion receives `(successCount, failureCount)`. |

## Models

### ConsentPreferences

```swift
public struct ConsentPreferences: Codable, Equatable {
    public var isCustomised: Bool
    public var cookieOptions: [CategoryConsent]

    public func isCategoryEnabled(_ categoryKey: String) -> Bool
}
```

### CategoryConsent

```swift
public struct CategoryConsent: Codable, Equatable {
    public let gtmKey: String
    public var isEnabled: Bool
}
```

### ConsentError

```swift
public enum ConsentError: LocalizedError {
    case notInitialized
    case invalidConfiguration(String)
    case invalidConfigUrl(String)
    case networkError(String)
    case parseError(String)
    case storageError(String)
    case validationError(String)
}
```

## Example Usage

### Save Preferences

```swift
let preferences = ConsentPreferences(
    isCustomised: true,
    cookieOptions: [
        CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
        CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: true),
        CategoryConsent(gtmKey: "dg-category-analytics", isEnabled: false)
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

### Show Consent Banner

```swift
DataGrailConsent.shared.showBanner(from: viewController, style: .modal) { preferences in
    if let prefs = preferences {
        print("User saved preferences: \(prefs)")
    } else {
        print("User dismissed without saving")
    }
}
```

### Check Category Status

```swift
if try DataGrailConsent.shared.isCategoryEnabled("dg-category-marketing") {
    enableMarketingTracking()
}
```

## Demo Project

A full-featured demo app is included under `DemoProject/`. To run it:

```bash
./launch_demo.sh          # Build and run
./launch_demo.sh --clean  # Clean build first
```

The demo app provides config URL input, banner display in both modal and fullscreen modes, live category status, and debug logging.

## Testing

```bash
swift test
```

## Architecture

The SDK uses a callback-based API for iOS 13+ compatibility with zero external dependencies.

- **Public API**: `DataGrailConsent` — singleton entry point
- **Manager**: `ConsentManager` — orchestrates config, storage, and network layers
- **Services**: `ConfigService`, `ConsentService` — config fetching and backend sync
- **Network**: `NetworkClient` — HTTP client with exponential backoff retry
- **Storage**: `ConsentStorage` — UserDefaults-based persistence with offline request queuing
- **UI**: `BannerViewController` — multi-layer consent banner with locale-aware translations
- **Models**: `ConsentConfig`, `ConsentPreferences`, `CategoryConsent`, `ConsentError`
- **Utils**: `ConfigValidator` — configuration validation

## License

Apache 2.0
