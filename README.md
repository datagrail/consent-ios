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
3. Select version `1.4.0`

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/datagrail/consent-ios.git", from: "1.4.0")
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
        if (try? DataGrailConsent.shared.shouldDisplayBanner()) == true {
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
if (try? DataGrailConsent.shared.isCategoryEnabled("dg-category-marketing")) == true {
    enableMarketingTracking()
}
```

## Requirements

**Runtime:**

- iOS 13.0+ or tvOS 13.0+
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
        CategoryConsent(gtmKey: "dg-category-performance", isEnabled: false)
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
if (try? DataGrailConsent.shared.isCategoryEnabled("dg-category-marketing")) == true {
    enableMarketingTracking()
}
```

## tvOS Support

The SDK includes full tvOS support with a D-pad-optimized banner and QR code pairing for phone-based consent management.

### Platform Support

- **iOS 13.0+** — Touch-based consent banner (modal/fullscreen)
- **tvOS 13.0+** — Focus-engine banner + optional QR pairing

### tvOS Quick Start

```swift
import DataGrailConsent

// Initialize with API key (required for QR pairing consent reads)
let configUrl = URL(string: "https://consent.datagrail.io/config/YOUR_CONFIG.json")!

DataGrailConsent.shared.initialize(
    configUrl: configUrl,
    apiKey: "your-api-key"  // Required for QR pairing
) { result in
    // Check initialization result
}

// Option 1: D-pad only banner (no QR pairing)
DataGrailConsent.shared.showBanner(from: viewController) { preferences in
    // User managed consent via D-pad navigation
}

// Option 2: Banner with QR pairing (phone can manage consent)
DataGrailConsent.shared.showBannerWithQRPairing(
    from: viewController,
    publicBaseUrl: "https://your-server.com",  // Reachable by phone
    configUrl: "https://your-server.com/config.json",
    customerId: "your-customer-id"
) { preferences in
    // User completed via QR scan + phone OR manual D-pad
}
```

### QR Pairing Flow

1. **TV displays banner** with QR code (generated from device `user_hash` + config URL)
2. **User scans QR** with phone camera
3. **Phone opens static page** showing category toggles (mobile-optimized)
4. **User manages preferences** on phone and saves
5. **TV polls** `GET /universal_consent` every 2 seconds
6. **TV detects phone's write** and auto-dismisses banner
7. **D-pad banner** remains available as fallback (10-minute client-side timeout)

#### Setup for Local Development

To test QR pairing locally with the [Universal Consent test server](https://github.com/datagrail/consent-test-server):

1. **Start the test server** on your Mac:
   ```bash
   cd /path/to/consent-test-server
   uv run uvicorn server:app --host 0.0.0.0 --port 8080
   ```

2. **Find your Mac's LAN IP**:
   ```bash
   ipconfig getifaddr en0  # e.g., 192.168.1.5
   ```

3. **Set `PUBLIC_BASE_URL` for the server**:
   ```bash
   PUBLIC_BASE_URL=http://192.168.1.5:8080 uv run uvicorn server:app --host 0.0.0.0 --port 8080
   ```

4. **In your tvOS app**, initialize with the LAN URLs:
   ```swift
   DataGrailConsent.shared.showBannerWithQRPairing(
       from: viewController,
       publicBaseUrl: "http://192.168.1.5:8080",
       configUrl: "http://192.168.1.5:8080/tv/sample-config.json",
       customerId: "cust-1"
   )
   ```

5. **For HTTPS** (required by some QR scanner apps):
   ```bash
   # Use cloudflared or ngrok for an HTTPS tunnel
   cloudflared tunnel --url http://localhost:8080
   # Then use the returned https://... URL as publicBaseUrl
   ```

#### tvOS Design Notes

- **Fonts**: Body ≥29pt, headings ≥38pt, buttons ≥66pt (10-foot viewing)
- **Focus engine**: All interactive elements focusable with scale+glow on focus
- **Menu button**: Navigates back or dismisses (no close button)
- **Category toggles**: Custom focusable rows (Select/left/right to toggle)
- **Essential categories**: Always-on categories render disabled (not focusable)

### tvOS Demo

A tvOS demo app is included under `DemoProject/DemoTvOS/`. Build it via:

```bash
xcodebuild build -scheme DemoTvOS -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
```

Or open in Xcode:
1. Generate Xcode project: `xcodegen` (in `DemoProject/`)
2. Select `DemoTvOS` scheme
3. Run on Apple TV simulator

The tvOS demo shows:
- Initialize with test server config
- Show D-pad banner (no QR)
- Show banner + QR pairing (scan with phone)
- Live category status panel
- Reset button

## Demo Project

A full-featured demo app is included under `DemoProject/`. To run the iOS demo:

```bash
./launch_demo.sh          # Build and run iOS demo
./launch_demo.sh --clean  # Clean build first
```

The demo app provides config URL input, banner display in both modal and fullscreen modes, live category status, and debug logging.

## Testing

```bash
swift test
```

## Architecture

The SDK uses a callback-based API for iOS 13+ / tvOS 13+ compatibility with zero external dependencies.

- **Public API**: `DataGrailConsent` — singleton entry point
- **Manager**: `ConsentManager` — orchestrates config, storage, and network layers
- **Services**: `ConfigService`, `ConsentService` — config fetching and backend sync
- **Network**: `NetworkClient` — HTTP client with exponential backoff retry
  - `PairingService` — QR URL generation + consent read polling (tvOS)
  - `PairingCoordinator` — polling loop, timeout, callbacks (tvOS)
- **Storage**: `ConsentStorage` — UserDefaults-based persistence with offline request queuing
- **UI**: 
  - `BannerViewController` — iOS multi-layer consent banner with locale-aware translations
  - `BannerViewControllerTvOS` — tvOS focus-engine banner with optional QR pairing
- **Models**: `ConsentConfig`, `ConsentPreferences`, `CategoryConsent`, `ConsentError`
- **Utils**: 
  - `ConfigValidator` — configuration validation
  - `UserHashGenerator` — SHA-256 device identity hash (tvOS)
  - `QRCodeGenerator` — Core Image QR code generation (tvOS)

## License

Apache 2.0
