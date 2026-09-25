# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Breaking:** `ConsentError.configNotPublished(statusCode:)`. A config fetch rejected with a definite 4xx (any 4xx except 408 and 429, including 403) when no cached config exists now fails with `.configNotPublished` instead of `.httpError`, and is not retried. With a cached config, the cache is still returned. Host apps that switch exhaustively over `ConsentError` must add the new case. Same name and trigger as Android `ConsentException.ConfigNotPublished` and React `CONFIG_NOT_PUBLISHED`.
- `Logger.error` on every config-load failure (fetch, parse, validation, 304 with no cache, cache write) and on `initialize` failure. Visible when `DataGrailConsent.logLevel` is `.error` or higher.

### Changed

- Fetched configs are now validated with `ConfigValidator` before being cached. An invalid config falls back to the cached config, or fails with `.validationError` if none exists, and is not retried.
- `ConfigValidator` (public) now accepts `ConsentLayerLanguagePickerElement` and applies per-type translation rules: link elements need non-empty `links`, each with translations; category, language picker, tracking details, and browser signal notice elements don't need top-level `translations`. Previously it rejected real published configs.
- A config-cache write failure no longer discards a freshly fetched, valid config.

### Fixed

- `initialize` now always delivers its completion on the main queue, on both success and failure.

## [1.7.0] - 2026-08-25

### Added

- Universal Consent (cross-device consent) support — opt-in `setUserIdentifier`, `fetchUniversalConsent`, and `rehydrateFromUniversalConsent` (both signed and api-key-only variants), plus a 30s ceiling on the customer-provided `getSignature` callback.

### Changed

- **Breaking:** `ConsentError` — non-2xx HTTP responses now surface as `.httpError(statusCode:message:)` instead of `.networkError`; adds the new `.httpError` and `.signatureTimeout` cases. Host apps that switch exhaustively over `ConsentError` must add the new cases. Breaking but low-impact, so shipped as a minor bump.
- Retry policy — a definite 4xx (other than 408 and 429) is no longer retried on config fetch, `savePreferences`, and `saveOpen`; it fails after one attempt. 408, 429, 5xx, and transport failures still retry.
- `rejectAll()` now treats a category as essential if `alwaysOn` is true OR its `gtmKey` contains "essential" (aligning with the banner's definition), so such a category stays enabled after reject-all instead of being disabled.
