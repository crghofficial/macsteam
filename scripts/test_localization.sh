#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d "${TMPDIR:-/tmp}/macsteam-l10n-check.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

RESOURCES="$PWD/macsteam-app/Sources/MacsteamApp/Resources"
for file in "$RESOURCES"/*.lproj/*; do
    plutil -lint "$file"
done
swiftc -swift-version 6 -parse-as-library \
    macsteam-app/Sources/MacsteamApp/L10n.swift \
    macsteam-app/Sources/MacsteamApp/MacsteamConfig.swift \
    scripts/localization_checks.swift -o "$TMP/localization-checks"
"$TMP/localization-checks" "$RESOURCES"

# Exercise both SwiftPM's embedded bundle and Xcode's main-bundle layout.
for mode in swiftpm xcode; do
    APP="$TMP/$mode.app"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>L10nProbe</string>
<key>CFBundleIdentifier</key><string>com.macsteam.localization-probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
</dict></plist>
PLIST
    FLAGS=()
    if [ "$mode" = swiftpm ]; then
        DEST="$APP/Contents/Resources/MacsteamApp_MacsteamApp.bundle"
        mkdir -p "$DEST"
        cp "$APP/Contents/Info.plist" "$DEST/Info.plist"
        FLAGS=(-D SWIFT_PACKAGE)
    else
        DEST="$APP/Contents/Resources"
    fi
    cp -R "$RESOURCES"/*.lproj "$DEST/"
    swiftc -swift-version 6 -parse-as-library ${FLAGS[@]+"${FLAGS[@]}"} \
        macsteam-app/Sources/MacsteamApp/L10n.swift \
        scripts/localization_bundle_check.swift -o "$APP/Contents/MacOS/L10nProbe"
    "$APP/Contents/MacOS/L10nProbe" -AppleLanguages '(en)' en
    "$APP/Contents/MacOS/L10nProbe" -AppleLanguages '(zh-Hans)' zh-Hans
done
