#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ARCH="$(uname -m)"
SDK="$(xcrun --show-sdk-path)"
APP="MyIPWidget.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -sdk "$SDK" -target "${ARCH}-apple-macos12.0" \
  -framework AppKit -framework Network -framework SystemConfiguration \
  -o "$APP/Contents/MacOS/MyIPWidget" \
  Sources/main.swift Sources/IPService.swift Sources/Widget.swift
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null
echo "built $(pwd)/$APP"
