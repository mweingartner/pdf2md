#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY_PATH="${ROOT_DIR}/.build/pdf2md"
APP_BUNDLE="${ROOT_DIR}/.build/PDF2MD.app"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pdf2md-smoke.XXXXXX")"
TEST_HOME="${TEST_ROOT}/home"
TEST_PDF="${TEST_ROOT}/sample.pdf"
TEST_MD="${TEST_ROOT}/sample.md"
INVALID_FILE="${TEST_ROOT}/not-a-pdf.txt"
WORKFLOW_PATH="${TEST_HOME}/Library/Services/Convert to Markdown.workflow"

cleanup() {
    rm -rf "${TEST_ROOT}"
}

trap cleanup EXIT

cat > "${TEST_PDF}" <<'EOF'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 44 >>
stream
BT
/F1 24 Tf
72 100 Td
(Hello PDF2MD) Tj
ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
0000000241 00000 n
0000000335 00000 n
trailer
<< /Root 1 0 R /Size 6 >>
startxref
405
%%EOF
EOF

printf 'not a pdf\n' > "${INVALID_FILE}"

echo "Smoke test: converting sample PDF"
"${BINARY_PATH}" "${TEST_PDF}" >/dev/null 2>&1

if [ ! -f "${TEST_MD}" ]; then
    echo "Smoke test failed: markdown output was not created at ${TEST_MD}" >&2
    exit 1
fi

if ! grep -q "Hello PDF2MD" "${TEST_MD}"; then
    echo "Smoke test failed: markdown output did not contain expected text" >&2
    exit 1
fi

echo "Smoke test: rejecting invalid input"
if "${BINARY_PATH}" "${INVALID_FILE}" >/dev/null 2>/dev/null; then
    echo "Smoke test failed: invalid input unexpectedly succeeded" >&2
    exit 1
fi

echo "Smoke test: generating workflow bundle"
mkdir -p "${TEST_HOME}/Library/Services"
HOME="${TEST_HOME}" PDF2MD_PATH="${BINARY_PATH}" bash "${ROOT_DIR}/Scripts/create-workflow.sh" >/dev/null

for path in \
    "${WORKFLOW_PATH}/Contents/Info.plist" \
    "${WORKFLOW_PATH}/Contents/Resources/document.wflow" \
    "${WORKFLOW_PATH}/Contents/version.plist"
do
    if [ ! -f "${path}" ]; then
        echo "Smoke test failed: missing workflow file ${path}" >&2
        exit 1
    fi
done

if ! plutil -extract NSServices.0.NSRequiredContext.NSApplicationIdentifier raw -o - \
    "${WORKFLOW_PATH}/Contents/Info.plist" | grep -qx "com.apple.finder"; then
    echo "Smoke test failed: workflow is not scoped to Finder" >&2
    exit 1
fi

if ! plutil -extract workflowMetaData.serviceInputTypeIdentifier raw -o - \
    "${WORKFLOW_PATH}/Contents/Resources/document.wflow" | grep -qx "com.apple.Automator.fileSystemObject.pdf"; then
    echo "Smoke test failed: workflow input type is incorrect" >&2
    exit 1
fi

echo "Smoke test: validating app bundle"
for path in \
    "${APP_BUNDLE}/Contents/Info.plist" \
    "${APP_BUNDLE}/Contents/MacOS/PDF2MD"
do
    if [ ! -f "${path}" ]; then
        echo "Smoke test failed: missing app bundle file ${path}" >&2
        exit 1
    fi
done

if ! plutil -extract LSUIElement raw -o - "${APP_BUNDLE}/Contents/Info.plist" | grep -Eqx "1|true"; then
    echo "Smoke test failed: app bundle is not configured as a background app" >&2
    exit 1
fi

if ! codesign -d --entitlements :- "${APP_BUNDLE}" 2>/dev/null | grep -q "com.apple.security.files.user-selected.read-write"; then
    echo "Smoke test failed: app bundle is missing user-selected file access entitlements" >&2
    exit 1
fi

echo "Smoke test passed."
