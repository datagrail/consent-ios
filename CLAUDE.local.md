# CLAUDE.local.md — TRUST-1843 (consent-ios surface)

You are running JAILED inside a shuru microVM (Linux). Your workspace is `/workspace` (a clone of consent-ios, on branch `TRUST-1843-tvos-qr`). The host knowledgebase is mounted at `/knowledgebase` — read specs there; write code only in `/workspace`.

## CRITICAL: Swift cannot compile in this Linux VM
There is no Swift/Xcode toolchain here, and tvOS only builds on macOS. **Do NOT try to run `swift build` or `xcodebuild` — they will fail and that is expected, not a blocker.** Your job is to produce correct, complete, well-structured **edits and commits**. The human verifies via `xcodebuild` on the host afterward. Reason about correctness from the existing code and the plan; do not treat inability-to-compile as a reason to stop.

## Harness: TRUST-1843
State: `/knowledgebase/projects/consent/.harness/TRUST-1843/` (read), mirrored at `/workspace/.harness/TRUST-1843/`.
This run works ONLY on features tagged `"repo": "consent-ios"` (feat-005..009).

### Session Start
1. Read `/knowledgebase/projects/consent/.harness/TRUST-1843/sources.json`, `progress.md`, `feature_list.json`.
2. Read the plan: `/knowledgebase/projects/consent/output/universal/tvos-qr-consent-local-buildout-plan.md` (Part B is your scope) and the wiki specs it references.
3. Skim the existing SDK layering in `/workspace/Sources/DataGrailConsent/` (DataGrailConsent.swift, ConsentManager.swift, Network/, UI/BannerViewController.swift, Models/, Storage/).
4. Pick the lowest-numbered consent-ios feature where `passes:false` and deps pass.

### Work Rules
- **WIP=1.** One feature at a time, in dependency order (feat-005 first — the platform must compile-guard cleanly before the banner/QR build on it).
- **Guardrails:** zero changes to existing iOS public API or behavior; existing iOS tests stay green; use `#if os(tvOS)` / `#if os(iOS)` COMPILE guards (never runtime checks); NO new external dependencies (generate QR with Core Image `CIFilter.qrCodeGenerator()`).
- GPC reconciliation is **client-side only**. Cover the `gpc:true` + `marketing:true`-in-store case where relevant.
- **Verification deferred to host:** since you can't compile, mark a feature `passes:true` only if the edits are COMPLETE and you are confident they satisfy the feature's intent; otherwise leave `passes:false` and note in progress.md what host verification is still required. Be honest — do not claim a build passes.
- **Commit after each feature** with a descriptive message.

### Session End
1. Commit all changes in `/workspace` (branch `TRUST-1843-tvos-qr`).
2. Update `/workspace/.harness/TRUST-1843/progress.md` and `feature_list.json` with status + a clear list of what the human must verify on the host (xcodebuild targets, the E2E demo).
