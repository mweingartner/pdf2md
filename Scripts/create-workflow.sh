#!/bin/bash
# create-workflow.sh
# Creates the Automator Quick Action workflow bundle for "Convert to Markdown"
# and installs it to ~/Library/Services/.
#
# The workflow receives PDF files selected in Finder and passes them to pdf2md.

set -euo pipefail

WORKFLOW_NAME="Convert to Markdown"
SERVICES_DIR="${HOME}/Library/Services"
BINARY_PATH="${PDF2MD_PATH:-/usr/local/bin/pdf2md}"
WORKFLOW_DIR="${SERVICES_DIR}/${WORKFLOW_NAME}.workflow"
CONTENTS_DIR="${WORKFLOW_DIR}/Contents"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Creating workflow bundle at: ${WORKFLOW_DIR}"

# Remove any previous version
rm -rf "${WORKFLOW_DIR}"

# Create directory structure
mkdir -p "${RESOURCES_DIR}"

# -------------------------------------------------------------------------
# Info.plist — modeled after Apple's own working Quick Actions
# Must include CFBundle keys for macOS to recognize the workflow bundle.
# -------------------------------------------------------------------------
cat > "${CONTENTS_DIR}/Info.plist" << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Convert to Markdown</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>en_US</string>
	<key>CFBundleIdentifier</key>
	<string>com.pdf2md.convert-to-markdown</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Convert to Markdown</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>com.adobe.pdf</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
INFOPLIST

# -------------------------------------------------------------------------
# document.wflow — Automator workflow definition
# Single "Run Shell Script" action, input passed as arguments.
# -------------------------------------------------------------------------
cat > "${RESOURCES_DIR}/document.wflow" << 'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.path</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.path</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>#!/bin/zsh
PDF2MD="BINARY_PATH_PLACEHOLDER"
if [ ! -x "$PDF2MD" ]; then
    osascript -e 'display dialog "pdf2md is not installed. Run: cd PROJECT_DIR_PLACEHOLDER &amp;&amp; make install" buttons {"OK"} default button "OK" with icon stop'
    exit 1
fi
status=0
for f in "$@"; do
    "$PDF2MD" "$f" 2>/dev/null
    if [ $? -eq 0 ]; then
        osascript -e "display notification \"Converted: $(basename "$f" .pdf).md\" with title \"PDF2MD\""
    else
        status=1
        osascript -e "display notification \"Failed to convert: $(basename "$f")\" with title \"PDF2MD\" subtitle \"Error\""
    fi
done
exit $status</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/zsh</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>B58C8C47-C527-4B58-82B1-4D9E8B6B1234</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>C69D9D58-D638-5C69-93C2-5EA9C7C2C345</string>
				<key>UUID</key>
				<string>D7AEAD69-E749-6D7A-A4ED-6FB0D8D3C456</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<true/>
				<key>location</key>
				<string>309.000000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<true/>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>serviceApplicationBundleID</key>
		<string>com.apple.finder</string>
		<key>serviceApplicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject.pdf</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

cat > "${CONTENTS_DIR}/version.plist" << 'VERSIONPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>BuildVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>ProjectName</key>
	<string>PDF2MD</string>
	<key>SourceVersion</key>
	<string>1</string>
</dict>
</plist>
VERSIONPLIST

# Substitute the actual binary path into the workflow
sed -i '' "s|BINARY_PATH_PLACEHOLDER|${BINARY_PATH}|g" "${RESOURCES_DIR}/document.wflow"
sed -i '' "s|PROJECT_DIR_PLACEHOLDER|${PROJECT_DIR}|g" "${RESOURCES_DIR}/document.wflow"

# Validate the plists
plutil -lint "${CONTENTS_DIR}/Info.plist" || { echo "Error: Info.plist is invalid"; exit 1; }
plutil -lint "${RESOURCES_DIR}/document.wflow" || { echo "Error: document.wflow is invalid"; exit 1; }
plutil -lint "${CONTENTS_DIR}/version.plist" || { echo "Error: version.plist is invalid"; exit 1; }

echo "Workflow bundle created successfully."
echo ""
echo "If the Quick Action doesn't appear in Finder's right-click menu:"
echo "  1. Open System Settings > Privacy & Security > Extensions > Finder"
echo "  2. Enable 'Convert to Markdown'"
echo "  3. Or try: killall Finder"
