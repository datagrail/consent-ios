# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `clearUserIdentifier()` — logout / return-to-neutral for Universal Consent (TRUST-2902). Clears the device's identity binding, returns local consent to the config default (banner shows again) and fires the consent-changed listener. Non-destructive, unlike `reset()`: no network call, the server-side record is untouched, and the unique id, config cache, version, locale and pending queue are kept. The SDK cannot detect a logout it is not told about, so hosts must call this on logout.

### Changed

- `setUserIdentifier` login rule (TRUST-2902). The device now persists the user hash (never the raw identifier) of the identity it is bound to, cleared by `reset()` and `clearUserIdentifier()`. On a login (device unbound or bound to a different identity): if a record is stored it is adopted locally and nothing from the device is written, even when a pre-login choice exists; if no record is stored, an explicit local choice (one the user saved on this device while it was not bound to a different identity) seeds the new record, and config defaults are never written. State left by a different bound identity is not written and local state returns to neutral. Once bound, local changes sync as before.
- `setUserIdentifier` with nothing to write now succeeds without writing, instead of failing with "No consent preferences to sync". The lower-level `ConsentManager.setUserIdentifier(_:apiKey:preferences:...)` write keeps that validation.
- Limitations: the SDK cannot tell whether a pre-login choice was made by the person logging in or by a previous user of a shared device (on a no-record login it attaches an explicit unbound choice by design), does no heuristic shared-device/shared-account detection, and cannot detect two people sharing one account.

## [1.7.0] - 2026-08-25

### Added

- Universal Consent (cross-device consent) support — opt-in `setUserIdentifier`, `fetchUniversalConsent`, and `rehydrateFromUniversalConsent` (both signed and api-key-only variants), plus a 30s ceiling on the customer-provided `getSignature` callback.

### Changed

- **Breaking:** `ConsentError` — non-2xx HTTP responses now surface as `.httpError(statusCode:message:)` instead of `.networkError`; adds the new `.httpError` and `.signatureTimeout` cases. Host apps that switch exhaustively over `ConsentError` must add the new cases. Breaking but low-impact, so shipped as a minor bump.
- Retry policy — a definite 4xx (other than 408 and 429) is no longer retried on config fetch, `savePreferences`, and `saveOpen`; it fails after one attempt. 408, 429, 5xx, and transport failures still retry.
- `rejectAll()` now treats a category as essential if `alwaysOn` is true OR its `gtmKey` contains "essential" (aligning with the banner's definition), so such a category stays enabled after reject-all instead of being disabled.
