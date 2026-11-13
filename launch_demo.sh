#!/bin/bash
set -e

usage() {
    cat <<EOF
Usage: ./launch_demo.sh [options]

  --clean               Clean build artifacts first
  --list                List available iOS simulators and exit
  --device <name|UDID>  Run on this simulator (exact name or UDID; see --list)
  --choose              Pick a simulator from a menu
  -h, --help            Show this help

With no device option, a booted iPhone is used, else an iPhone 16 Pro, else the first available iPhone.
EOF
}

# Prints one line per available iOS simulator: UDID|name|runtime|state
list_devices() {
    local header_re='^--[[:space:]]+(.+)[[:space:]]+--$'
    local device_re='^[[:space:]]+(.+)[[:space:]]\(([0-9A-Fa-f-]{36})\)[[:space:]]\((.+)\)[[:space:]]*$'
    local runtime="" line
    while IFS= read -r line; do
        if [[ $line =~ $header_re ]]; then
            runtime="${BASH_REMATCH[1]}"
        elif [[ $runtime == iOS* && $line =~ $device_re ]]; then
            echo "${BASH_REMATCH[2]}|${BASH_REMATCH[1]}|$runtime|${BASH_REMATCH[3]}"
        fi
    done < <(xcrun simctl list devices available)
}

print_devices() {
    list_devices | while IFS='|' read -r udid name runtime state; do
        printf '%-24s %-10s %-10s %s\n' "$name" "$runtime" "$state" "$udid"
    done
}

# Resolve a UDID or exact name to a UDID, preferring a booted match
resolve_device() {
    local query="$1" udid name runtime state match="" match_state=""
    while IFS='|' read -r udid name runtime state; do
        if [[ "$udid" == "$query" ]]; then
            echo "$udid"
            return 0
        fi
        if [[ "$name" == "$query" ]]; then
            if [[ -z "$match" || ( "$state" == "Booted" && "$match_state" != "Booted" ) ]]; then
                match="$udid"
                match_state="$state"
            fi
        fi
    done < <(list_devices)
    # Always succeed: the caller checks for an empty result (set -e would otherwise exit silently)
    if [[ -n "$match" ]]; then echo "$match"; fi
    return 0
}

# Parse arguments
CLEAN_BUILD=false
LIST_ONLY=false
CHOOSE=false
REQUESTED_DEVICE=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --clean) CLEAN_BUILD=true ;;
        --list) LIST_ONLY=true ;;
        --choose) CHOOSE=true ;;
        --device)
            if [[ -z "${2:-}" ]]; then echo "--device needs a name or UDID"; exit 1; fi
            REQUESTED_DEVICE="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

if [ "$LIST_ONLY" = true ]; then
    print_devices
    exit 0
fi

SELECTED_DEVICE_ID=""
if [ -n "$REQUESTED_DEVICE" ]; then
    SELECTED_DEVICE_ID=$(resolve_device "$REQUESTED_DEVICE")
    if [ -z "$SELECTED_DEVICE_ID" ]; then
        echo "No available simulator matches '$REQUESTED_DEVICE'. Available simulators:"
        print_devices
        exit 1
    fi
elif [ "$CHOOSE" = true ]; then
    CHOICES=()
    while IFS= read -r entry; do CHOICES+=("$entry"); done < <(list_devices)
    if [ "${#CHOICES[@]}" -eq 0 ]; then
        echo "No available iOS simulators found."
        exit 1
    fi
    LABELS=()
    for entry in "${CHOICES[@]}"; do
        IFS='|' read -r udid name runtime state <<< "$entry"
        LABELS+=("$name ($runtime, $state)")
    done
    PS3="Select a simulator: "
    select _ in "${LABELS[@]}"; do
        if [[ -n "$REPLY" && "$REPLY" -ge 1 && "$REPLY" -le "${#CHOICES[@]}" ]] 2>/dev/null; then
            SELECTED_DEVICE_ID="${CHOICES[$((REPLY - 1))]%%|*}"
            break
        fi
        echo "Enter a number from the list."
    done
    if [ -z "$SELECTED_DEVICE_ID" ]; then
        echo "No simulator selected."
        exit 1
    fi
fi

echo "Building and launching Demo app..."

# Navigate to iOS directory
cd "$(dirname "$0")"

# Check if XcodeGen is available
if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Please install it with: brew install xcodegen"
    exit 1
fi

cd DemoProject

echo "Generating Xcode project with XcodeGen..."
xcodegen generate

# An explicitly selected device (--device / --choose) wins; otherwise find a booted iPhone simulator, or boot one
DEVICE_ID="$SELECTED_DEVICE_ID"

if [ -n "$DEVICE_ID" ]; then
    echo "Booting selected simulator: $DEVICE_ID"
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
    sleep 2
else
    DEVICE_ID=$(xcrun simctl list devices | grep -E "iPhone.*(Booted)" | grep -v "Pro Max" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')
fi

if [ -z "$DEVICE_ID" ]; then
    echo "No booted simulator found, finding an iPhone 16 Pro..."
    DEVICE_ID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | grep -v "Pro Max" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')

    if [ -z "$DEVICE_ID" ]; then
        echo "No iPhone 16 Pro simulator found, using first available iPhone..."
        DEVICE_ID=$(xcrun simctl list devices | grep "iPhone" | grep -v unavailable | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')
    fi

    echo "Booting simulator: $DEVICE_ID"
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
    sleep 2
fi

echo "Using simulator: $DEVICE_ID"

if [ "$CLEAN_BUILD" = true ]; then
    echo "Cleaning build artifacts..."
    rm -rf ./build
    rm -rf ~/Library/Developer/Xcode/DerivedData/Demo-*
    xcodebuild clean -scheme Demo 2>/dev/null || true
fi

echo "Building Demo app..."
xcodebuild -scheme Demo -derivedDataPath ./build -destination "id=$DEVICE_ID" 2>&1 | grep -E '(BUILD|error:|warning:)' || true

# Check if build succeeded
APP_PATH="./build/Build/Products/Debug-iphonesimulator/Demo.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Build may have failed. Running full build output:"
    xcodebuild -scheme Demo -derivedDataPath ./build -destination "id=$DEVICE_ID"
fi

echo "Installing app to simulator..."
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

echo "Launching Demo app..."
xcrun simctl launch "$DEVICE_ID" io.datagrail.consent.demo

echo "Demo app launched successfully!"
# Xcode 27 replaced the standalone Simulator app with DeviceHub
open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null || echo "Could not open Simulator or DeviceHub; open one manually."
