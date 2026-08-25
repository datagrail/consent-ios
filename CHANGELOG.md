# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.0] - 2026-08-25

### Added

- Universal Consent (cross-device consent) support — opt-in `setUserIdentifier`, `fetchUniversalConsent`, and `rehydrateFromUniversalConsent` (both signed and api-key-only variants), plus a 30s ceiling on the customer-provided `getSignature` callback.

### Changed

- **Breaking:** `ConsentError` — non-2xx HTTP responses now surface as `.httpError(statusCode:message:)` instead of `.networkError`; adds the new `.httpError` and `.signatureTimeout` cases. Host apps that switch exhaustively over `ConsentError` must add the new cases. Breaking but low-impact, so shipped as a minor bump.
- Retry policy — a definite 4xx (other than 408 and 429) is no longer retried on config fetch, `savePreferences`, and `saveOpen`; it fails after one attempt. 408, 429, 5xx, and transport failures still retry.
- `rejectAll()` now treats a category as essential if `alwaysOn` is true OR its `gtmKey` contains "essential" (aligning with the banner's definition), so such a category stays enabled after reject-all instead of being disabled.
