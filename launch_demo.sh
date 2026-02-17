#!/bin/bash
set -e

# Parse arguments
CLEAN_BUILD=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --clean) CLEAN_BUILD=true ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

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

# Find first available booted iPhone simulator, or boot one
DEVICE_ID=$(xcrun simctl list devices | grep -E "iPhone.*(Booted)" | grep -v "Pro Max" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')

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
open -a Simulator
