#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build"
APP_NAME="PDF2MD"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
EXECUTABLE_PATH="${MACOS_DIR}/${APP_NAME}"
ENTITLEMENTS_PATH="${ROOT_DIR}/Scripts/PDF2MDMonitor.entitlements"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"

swiftc -O -o "${EXECUTABLE_PATH}" \
    "${ROOT_DIR}/Sources/ConversionError.swift" \
    "${ROOT_DIR}/Sources/PDFConversionService.swift" \
    "${ROOT_DIR}/Sources/PDFExtractor.swift" \
    "${ROOT_DIR}/Sources/MarkdownFormatter.swift" \
    "${ROOT_DIR}/Sources/TextCleaner.swift" \
    "${ROOT_DIR}/Sources/App/MonitorConfiguration.swift" \
    "${ROOT_DIR}/Sources/App/MonitorEvent.swift" \
    "${ROOT_DIR}/Sources/App/MonitorLogEntry.swift" \
    "${ROOT_DIR}/Sources/App/PDFMonitorService.swift" \
    "${ROOT_DIR}/Sources/App/PDF2MDAppModel.swift" \
    "${ROOT_DIR}/Sources/App/MonitorDashboardView.swift" \
    "${ROOT_DIR}/Sources/App/PDF2MDMonitorApp.swift" \
    -framework SwiftUI \
    -framework AppKit \
    -framework PDFKit

cat > "${CONTENTS_DIR}/Info.plist" <<'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>PDF2MD</string>
	<key>CFBundleIdentifier</key>
	<string>com.pdf2md.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>PDF2MD</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSDesktopFolderUsageDescription</key>
	<string>PDF2MD monitors and converts PDFs in folders you choose, including the Desktop.</string>
	<key>NSDocumentsFolderUsageDescription</key>
	<string>PDF2MD monitors and converts PDFs in folders you choose, including Documents.</string>
	<key>NSDownloadsFolderUsageDescription</key>
	<string>PDF2MD monitors and converts PDFs in folders you choose, including Downloads.</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSNetworkVolumesUsageDescription</key>
	<string>PDF2MD needs access to network folders you select for monitoring, output, or archiving.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSRemovableVolumesUsageDescription</key>
	<string>PDF2MD needs access to removable drives you select for monitoring, output, or archiving.</string>
</dict>
</plist>
INFOPLIST

codesign --force --sign - --entitlements "${ENTITLEMENTS_PATH}" "${APP_BUNDLE}"
