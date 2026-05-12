#!/bin/bash
set -euo pipefail

APP_NAME="MacPolish"
VERSION="${GITHUB_REF_NAME:-dev}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
APP_PATH="build/export/${APP_NAME}.app"
DMG_PATH="build/${DMG_NAME}"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP_PATH} not found"
    exit 1
fi

create-dmg \
    --volname "${APP_NAME}" \
    --volicon "${APP_PATH}/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 175 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 425 190 \
    --no-internet-enable \
    "${DMG_PATH}" \
    "build/export/" \
    || true

if [ -f "$DMG_PATH" ]; then
    echo "DMG created: ${DMG_PATH}"
    ls -lh "$DMG_PATH"
else
    echo "Warning: create-dmg may have failed, falling back to hdiutil"
    hdiutil create -volname "${APP_NAME}" -srcfolder "build/export/" -ov -format UDZO "${DMG_PATH}"
fi
