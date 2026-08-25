# Universal Consent — iOS demo client (setup & run)

The iOS half of the Universal Consent cross-client demo (TRUST-1843). Set consent
for an email here and read it back on the web client (see the `consent-banner`
repo, `demo/universal/README.md`) — the same `user_hash` shares the same record.

## 1. What you need

- macOS with **Xcode 16** and an **iOS 18 simulator** (examples use *iPhone 16 Pro*).
- The demo config values — obtain from the demo owner / team secret store; they
  are **not** committed to git. Same values as the web client:
  `UC_DEMO_API_KEY`, `UC_DEMO_SIGNER_URL`, `UC_DEMO_CONSENT_API_HOST`,
  `UC_DEMO_CUSTOMER_ID`, `UC_DEMO_PROJECT_ID`.

AWS access is not needed to run the demo (it hits the public edge + signer).

## 2. Configure

```sh
cd DemoProject
cp demo-env.example.sh demo-env.local.sh
# edit demo-env.local.sh and fill in the real values
```

`demo-env.local.sh` is gitignored. Values are read at launch from `UC_DEMO_*`
environment variables (see `DemoConfig.env()` in `Demo/ContentView.swift`);
missing values fall back to loud placeholders.

## 3. Boot a simulator and get its UDID

```sh
xcrun simctl boot "iPhone 16 Pro"
xcrun simctl list devices booted        # copy the UDID of the booted device
open -a Simulator                        # optional: show the simulator window
```

> **Use the UDID, not the device name, when building.** Several "iPhone 16 Pro"
> runtimes are usually installed (18.3.1 / 18.4 / 18.5), so
> `-destination 'name=iPhone 16 Pro'` is *ambiguous* — xcodebuild then no-ops
> with exit 0 and produces no `.app`. Always use `-destination 'id=<UDID>'`.

## 4. Build

```sh
xcodebuild -project Demo.xcodeproj -scheme Demo -sdk iphonesimulator \
  -destination 'id=<YOUR_BOOTED_SIM_UDID>' -derivedDataPath /tmp/uc-ios-dd build
```

> A SourceKit warning "No such module 'DataGrailConsent'" in the editor is
> indexer noise — `xcodebuild` resolves the local Swift package fine.

## 5. Install and launch **with the env forwarded**

`xcrun simctl launch` only passes variables prefixed `SIMCTL_CHILD_` into the app:

```sh
source ./demo-env.local.sh
xcrun simctl install booted /tmp/uc-ios-dd/Build/Products/Debug-iphonesimulator/Demo.app
SIMCTL_CHILD_UC_DEMO_API_KEY="$UC_DEMO_API_KEY" \
SIMCTL_CHILD_UC_DEMO_SIGNER_URL="$UC_DEMO_SIGNER_URL" \
SIMCTL_CHILD_UC_DEMO_CONSENT_API_HOST="$UC_DEMO_CONSENT_API_HOST" \
SIMCTL_CHILD_UC_DEMO_CUSTOMER_ID="$UC_DEMO_CUSTOMER_ID" \
SIMCTL_CHILD_UC_DEMO_PROJECT_ID="$UC_DEMO_PROJECT_ID" \
  xcrun simctl launch booted io.datagrail.consent.demo
```

> **Launching by tapping the app icon in the Simulator will NOT carry the env**,
> so the app then shows placeholders and "signer not configured". Relaunch with
> the command above to run against the real environment.

## 6. Use it / round-trip

1. Enter a user email, toggle Analytics / Marketing, **Save**.
2. **Refresh / Read** — the toggles and readout reflect the stored record.
3. Enter the **same email** on the web client and Read → same `user_hash`, same
   consent. Use a fresh email to demonstrate first-write sharing.

## 7. Troubleshooting

- **No `.app` after a "successful" build** — ambiguous `-destination`; use
  `id=<UDID>` (see step 3).
- **App shows placeholders / "signer not configured"** — launched without env
  (icon tap). Relaunch with the `SIMCTL_CHILD_*` command in step 5.
- **Reading an old email shows unfamiliar category keys** — that record was
  written by an older client. Current clients use `dg-category-performance` /
  `dg-category-marketing`. Use a fresh email.
