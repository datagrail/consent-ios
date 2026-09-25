# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Breaking:** `ConsentError.configNotPublished(statusCode:)`. A config fetch rejected with a definite 4xx (any 4xx except 408 and 429, including 403) when no cached config exists now fails with `.configNotPublished` instead of `.httpError`, and is not retried. With a cached config, the cache is still returned. Host apps that switch exhaustively over `ConsentError` must add the new case. Same name and trigger as Android `ConsentException.ConfigNotPublished` and React `CONFIG_NOT_PUBLISHED`.
- `Logger.error` on every config-load failure (fetch, parse, validation, 304 with no cache, cache write) and on `initialize` failure. Visible when `DataGrailConsent.logLevel` is `.error` or higher.
- Demo app: a **Config URL** tab that loads a pre-signed test config link from the Mobile tab and previews it with the SDK's banner, showing the SDK and config schema versions and a specific error for expired, altered, deleted, unreachable, unparseable, or unsupported-schema links. Demo-only; the SDK's public API is unchanged.
- `clearUserIdentifier()` — logout / return-to-neutral for Universal Consent (TRUST-2902). Clears the device's identity binding, returns local consent to the config default (banner shows again) and fires the consent-changed listener. Non-destructive, unlike `reset()`: no network call, the server-side record is untouched, and the unique id, config cache, version, locale and pending queue are kept. The SDK cannot detect a logout it is not told about, so hosts must call this on logout.

### Changed

- Fetched configs are now validated with `ConfigValidator` before being cached. An invalid config falls back to the cached config, or fails with `.validationError` if none exists, and is not retried.
- `ConfigValidator` (public) now accepts `ConsentLayerLanguagePickerElement` and applies per-type translation rules: link elements need non-empty `links`, each with translations; category, language picker, tracking details, and browser signal notice elements don't need top-level `translations`. Previously it rejected real published configs.
- A config-cache write failure no longer discards a freshly fetched, valid config.
- `setUserIdentifier` login rule (TRUST-2902). The device now persists the user hash (never the raw identifier) of the identity it is bound to, cleared by `reset()` and `clearUserIdentifier()`. On a login (device unbound or bound to a different identity): if a record is stored it is adopted locally and nothing from the device is written, even when a pre-login choice exists; if no record is stored, an explicit local choice (one the user saved on this device while it was not bound to a different identity) seeds the new record, and config defaults are never written. State left by a different bound identity is not written and local state returns to neutral. Once bound, local changes sync as before.
- `setUserIdentifier` with nothing to write now succeeds without writing, instead of failing with "No consent preferences to sync". The lower-level `ConsentManager.setUserIdentifier(_:apiKey:preferences:...)` write keeps that validation.
- Limitations: the SDK cannot tell whether a pre-login choice was made by the person logging in or by a previous user of a shared device (on a no-record login it attaches an explicit unbound choice by design), does no heuristic shared-device/shared-account detection, and cannot detect two people sharing one account.

### Fixed

- `initialize` now always delivers its completion on the main queue, on both success and failure.

## [1.7.0] - 2026-08-25

### Added

- Universal Consent (cross-device consent) support — opt-in `setUserIdentifier`, `fetchUniversalConsent`, and `rehydrateFromUniversalConsent` (both signed and api-key-only variants), plus a 30s ceiling on the customer-provided `getSignature` callback.

### Changed

- **Breaking:** `ConsentError` — non-2xx HTTP responses now surface as `.httpError(statusCode:message:)` instead of `.networkError`; adds the new `.httpError` and `.signatureTimeout` cases. Host apps that switch exhaustively over `ConsentError` must add the new cases. Breaking but low-impact, so shipped as a minor bump.
- Retry policy — a definite 4xx (other than 408 and 429) is no longer retried on config fetch, `savePreferences`, and `saveOpen`; it fails after one attempt. 408, 429, 5xx, and transport failures still retry.
- `rejectAll()` now treats a category as essential if `alwaysOn` is true OR its `gtmKey` contains "essential" (aligning with the banner's definition), so such a category stays enabled after reject-all instead of being disabled.
