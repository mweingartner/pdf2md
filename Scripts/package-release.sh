#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build"
DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="PDF2MD"
CLI_NAME="pdf2md"
CLI_ARCHIVE="${DIST_DIR}/${CLI_NAME}-macos-arm64.tar.gz"
APP_ARCHIVE="${DIST_DIR}/${APP_NAME}-macos-arm64.zip"
CHECKSUMS_FILE="${DIST_DIR}/SHA256SUMS.txt"

PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/sbin:/sbin

cd "${ROOT_DIR}"

/usr/bin/make build build-app

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

/usr/bin/tar -C "${BUILD_DIR}" -czf "${CLI_ARCHIVE}" "${CLI_NAME}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${BUILD_DIR}/${APP_NAME}.app" "${APP_ARCHIVE}"

(
    cd "${DIST_DIR}"
    /usr/bin/shasum -a 256 "$(basename "${CLI_ARCHIVE}")" "$(basename "${APP_ARCHIVE}")" > "${CHECKSUMS_FILE}"
)

echo "Created release artifacts:"
echo "  ${CLI_ARCHIVE}"
echo "  ${APP_ARCHIVE}"
echo "  ${CHECKSUMS_FILE}"
