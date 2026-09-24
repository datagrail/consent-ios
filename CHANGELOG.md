# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `clearUserIdentifier()` — logout / return-to-neutral for Universal Consent (TRUST-2902). Clears the device's identity binding and returns local consent to the config default (banner shows again) and fires the consent-changed listener. Non-destructive, unlike `reset()`: no network call, the server-side record is untouched, and the unique id, config cache, version, locale and pending queue are kept. The SDK cannot detect a logout it is not told about, so hosts must call this on logout.
- `setUserIdentifier(..., attachAnonymousConsent: Bool = false)` — opt-in to attributing a pre-login local choice to the logging-in identity.

### Changed

- `setUserIdentifier` no longer attributes pre-login anonymous consent to a new identity (TRUST-2902). When no record is stored for the identifier and the device is not already bound to it, an existing local choice is not written to the record; local state returns to neutral instead. The SDK cannot tell whether that choice was made by the person logging in or by a previous user of a shared device, and does no shared-device/shared-account detection; pass `attachAnonymousConsent: true` only when your app knows the choice and the login happened in one session. Found-record behavior is unchanged. The device persists only the user hash of the bound identity (cleared by `reset()` and `clearUserIdentifier()`).

## [1.7.0] - 2026-08-25

### Added

- Universal Consent (cross-device consent) support — opt-in `setUserIdentifier`, `fetchUniversalConsent`, and `rehydrateFromUniversalConsent` (both signed and api-key-only variants), plus a 30s ceiling on the customer-provided `getSignature` callback.

### Changed

- **Breaking:** `ConsentError` — non-2xx HTTP responses now surface as `.httpError(statusCode:message:)` instead of `.networkError`; adds the new `.httpError` and `.signatureTimeout` cases. Host apps that switch exhaustively over `ConsentError` must add the new cases. Breaking but low-impact, so shipped as a minor bump.
- Retry policy — a definite 4xx (other than 408 and 429) is no longer retried on config fetch, `savePreferences`, and `saveOpen`; it fails after one attempt. 408, 429, 5xx, and transport failures still retry.
- `rejectAll()` now treats a category as essential if `alwaysOn` is true OR its `gtmKey` contains "essential" (aligning with the banner's definition), so such a category stays enabled after reject-all instead of being disabled.
