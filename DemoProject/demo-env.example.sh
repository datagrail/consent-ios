# Universal Consent iOS demo — local env TEMPLATE.
#
# Copy to demo-env.local.sh (gitignored), fill in your stage/demo values, then
# build + install + launch with the env forwarded into the simulator app.
#
#   cp demo-env.example.sh demo-env.local.sh   # then edit demo-env.local.sh
#   source demo-env.local.sh
#
# `xcrun simctl launch` only forwards vars prefixed with SIMCTL_CHILD_ into the
# app process, so launch like this (note: launching by tapping the icon in the
# Simulator GUI will NOT carry these — the app then shows the placeholders):
#
#   xcodebuild -project Demo.xcodeproj -scheme Demo -sdk iphonesimulator \
#     -destination 'id=<YOUR_BOOTED_SIM_UDID>' -derivedDataPath /tmp/uc-ios-dd build
#   xcrun simctl install booted /tmp/uc-ios-dd/Build/Products/Debug-iphonesimulator/Demo.app
#   SIMCTL_CHILD_UC_DEMO_API_KEY="$UC_DEMO_API_KEY" \
#   SIMCTL_CHILD_UC_DEMO_SIGNER_URL="$UC_DEMO_SIGNER_URL" \
#   SIMCTL_CHILD_UC_DEMO_CONSENT_API_HOST="$UC_DEMO_CONSENT_API_HOST" \
#   SIMCTL_CHILD_UC_DEMO_CUSTOMER_ID="$UC_DEMO_CUSTOMER_ID" \
#   SIMCTL_CHILD_UC_DEMO_PROJECT_ID="$UC_DEMO_PROJECT_ID" \
#     xcrun simctl launch booted io.datagrail.consent.demo

export UC_DEMO_API_KEY="YOUR_DEMO_API_KEY"
export UC_DEMO_SIGNER_URL="https://YOUR_SIGNER_HOST"
export UC_DEMO_CONSENT_API_HOST="your-edge-host.cloudfront.net"   # host only, no scheme
export UC_DEMO_CUSTOMER_ID="YOUR_DG_CUSTOMER_ID"
export UC_DEMO_PROJECT_ID="uc-demo"
