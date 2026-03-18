# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DataGrail Consent iOS SDK — a native iOS library for displaying consent banners and managing user privacy preferences. Distributed via CocoaPods and Swift Package Manager. Zero external dependencies, callback-based API, targets iOS 13+, Swift 5.7+.

## Build & Test Commands

```bash
swift build                  # Build the package
swift test                   # Run all tests (non-UI)
swiftlint lint --strict      # Lint (CI runs with --strict)
```

UIKit tests (BannerViewController tests) require an iOS simulator:
```bash
xcodebuild test \
  -scheme DataGrailConsent \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -enableCodeCoverage YES
```

Demo app:
```bash
./launch_demo.sh             # Build and run demo
./launch_demo.sh --clean     # Clean build first
```

Podspec validation:
```bash
pod lib lint --allow-warnings
```

## Architecture

```
Sources/DataGrailConsent/
├── DataGrailConsent.swift       # Public singleton API — all external access goes through here
├── ConsentManager.swift         # Orchestrator: coordinates config, storage, network
├── Models/
│   ├── ConsentConfig.swift      # Remote config JSON models (deeply nested: Layout → ConsentLayer → ConsentLayerElement)
│   ├── ConsentPreferences.swift # User consent state (isCustomised + [CategoryConsent])
│   └── ConsentError.swift       # Error enum
├── Network/
│   ├── NetworkClient.swift      # HTTP client with exponential backoff retry
│   ├── ConfigService.swift      # Fetches remote config JSON
│   └── ConsentService.swift     # Syncs preferences to backend, tracks events
├── Storage/
│   └── ConsentStorage.swift     # UserDefaults persistence + offline request queuing
├── UI/
│   └── BannerViewController.swift  # Multi-layer consent banner (UIKit, locale-aware)
└── Utils/
    └── ConfigValidator.swift    # Config validation
```

**Key data flow:** `DataGrailConsent.shared.initialize(configUrl:)` → `ConsentManager.loadConfig()` → `ConfigService.fetchConfigWithRetry()` → config stored in memory → banner can be shown → user preferences saved locally via `ConsentStorage` and synced to backend via `ConsentService`.

**Config model hierarchy:** `ConsentConfig` → `Layout` → `[String: ConsentLayer]` → `[ConsentLayerElement]`. Elements are polymorphic (text, button, link, category) distinguished by the `type` field. Categories use `gtmKey` as the canonical identifier.

## Test Structure

Tests mirror source layout under `Tests/DataGrailConsentTests/`. Test config fixtures are JSON files in `Tests/DataGrailConsentTests/Resources/` (registered as `.copy` resources in Package.swift).

UI tests (under `Tests/.../UI/`) test `BannerViewController` and require UIKit — they run via `xcodebuild` on a simulator, not `swift test`.

## CI (GitHub Actions)

PR checks run 4 jobs: build & test (`swift test`), SwiftLint (`--strict`), UIKit simulator tests (`xcodebuild test`), and podspec validation (`pod lib lint`).

## Conventions

- SwiftLint configured in `.swiftlint.yml` — note custom rules: no `print()` (use proper logging), no force casts (`as!`), no force try (`try!`)
- Line length: 120 warning, 150 error
- Version is tracked in `DataGrailConsent.podspec` (currently 1.1.0)
- `#if canImport(UIKit)` guards around UI code for cross-platform compilation
- Config JSON uses `snake_case` keys mapped via `CodingKeys` to Swift `camelCase`
