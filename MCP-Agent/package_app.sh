#!/bin/bash

APP_NAME="BuddyMCP"
BUILD_DIR=".build/arm64-apple-macosx/debug" # Or release
OUTPUT_DIR="."
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"

echo "Building ${APP_NAME}..."
swift build -c debug # Use release for optimized build

if [ $? -ne 0 ]; then
    echo "Build failed."
    exit 1
fi

echo "Creating App Bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

echo "Copying executable..."
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

echo "Copying resources..."
# Copy python agent core if needed
mkdir -p "${APP_BUNDLE}/Contents/Resources/AgentCore"
cp AgentCore/agent_core.py "${APP_BUNDLE}/Contents/Resources/AgentCore/"

echo "Creating Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.johnnyclem.${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Signing app bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "Done! App saved to ${APP_BUNDLE}"
echo "You can move this to your Applications folder."
