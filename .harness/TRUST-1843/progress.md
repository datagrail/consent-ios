# Progress: TRUST-1843 — tvOS QR-Pairing Consent (Local Buildout)

## Spec
Build the full CTV QR-consent loop locally. Add a tvOS target to consent-ios (D-pad banner + QR-pairing layer) and extend the local Universal Consent test server with a fully static phone consent page (reads user_hash/customer_id/config_url from the querystring), direct-read polling, and an SSE push endpoint. TV shows a QR → phone scans → static page writes consent → TV detects via polling and applies. No pairing-session subsystem. See `output/universal/tvos-qr-consent-local-buildout-plan.md`.

## Surfaces
- **consent-test-server** (feat-001..004): FastAPI/`uv`, lives at `output/universal/test-server/` inside the knowledgebase repo. Linux-native — agent edits AND self-verifies with curl in-VM.
- **consent-ios** (feat-005..009): Swift/tvOS at `~/proj/consent-ios`. Swift can't compile in a Linux VM — agent does edits+commits only; human verifies via `xcodebuild` on the host.

## Status
| ID | Repo | Description | Passes |
|----|------|-------------|--------|
| feat-001 | consent-test-server | PUBLIC_BASE_URL + StaticFiles /tv mount | [ ] |
| feat-002 | consent-test-server | Static phone page (index.html + consent.js + sample-config.json) | [ ] |
| feat-003 | consent-test-server | SSE /universal_consent/events (keyed on user_hash) | [ ] |
| feat-004 | consent-test-server | Pairing tests + README run book | [ ] |
| feat-005 | consent-ios | tvOS target compiles (guards) | [ ] |
| feat-006 | consent-ios | Full tvOS D-pad banner | [ ] |
| feat-007 | consent-ios | QR pairing layer (PairingService/Coordinator/QR + adoptRemotePreferences) | [ ] |
| feat-008 | consent-ios | tvOS + pairing tests, CI jobs | [ ] |
| feat-009 | consent-ios | tvOS demo target + docs | [ ] |

## Current Session
**Active feature:** (none yet — scaffolding)
**Decisions made:**
- QR carries user_hash directly; no session subsystem (per plan §0).
- SDK polls; server also exposes SSE (built, unused by SDK v1).
- iOS verification deferred to host (xcodebuild); VM produces edits+commits only.
**Blockers:** (none)

## Session Log
- 2026-05-31 (host, planning): Scaffolded harness from the buildout plan. 9 features decomposed across 2 surfaces. Execution model: shuru VM per surface; server self-verifies, iOS verified on host.
