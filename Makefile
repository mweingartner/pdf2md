BINARY_NAME = pdf2md
APP_NAME = PDF2MD
BUILD_DIR = .build
INSTALL_DIR = /usr/local/bin
USER_INSTALL_DIR = $(HOME)/.local/bin
USER_APP_DIR = $(HOME)/Applications
SYSTEM_APP_DIR = /Applications
APP_ENTITLEMENTS = Scripts/PDF2MDMonitor.entitlements
WORKFLOW_NAME = Convert to Markdown
SERVICES_DIR = $(HOME)/Library/Services

.PHONY: all build build-app verify install uninstall clean

all: build build-app

build:
	@mkdir -p $(BUILD_DIR)
	swiftc -O -o $(BUILD_DIR)/$(BINARY_NAME) \
		Sources/ConversionError.swift \
		Sources/PDFConversionService.swift \
		Sources/main.swift \
		Sources/PDFExtractor.swift \
		Sources/MarkdownFormatter.swift \
		Sources/TextCleaner.swift \
		-framework PDFKit \
		-framework AppKit

build-app:
	bash Scripts/build-app.sh

verify: build build-app
	bash Scripts/smoke-test.sh

install: build build-app
	@mkdir -p $(USER_INSTALL_DIR)
	@echo "Installing $(BINARY_NAME) to $(USER_INSTALL_DIR)..."
	cp $(BUILD_DIR)/$(BINARY_NAME) $(USER_INSTALL_DIR)/$(BINARY_NAME)
	chmod 755 $(USER_INSTALL_DIR)/$(BINARY_NAME)
	@# Ad-hoc code sign to satisfy Gatekeeper (Security H-2)
	codesign --force --sign - $(USER_INSTALL_DIR)/$(BINARY_NAME)
	@echo "Creating Quick Action workflow..."
	PDF2MD_PATH="$(USER_INSTALL_DIR)/$(BINARY_NAME)" bash Scripts/create-workflow.sh
	@mkdir -p "$(USER_APP_DIR)"
	@echo "Installing $(APP_NAME).app to $(USER_APP_DIR)..."
	rm -rf "$(USER_APP_DIR)/$(APP_NAME).app"
	cp -R "$(BUILD_DIR)/$(APP_NAME).app" "$(USER_APP_DIR)/$(APP_NAME).app"
	codesign --force --sign - --entitlements "$(APP_ENTITLEMENTS)" "$(USER_APP_DIR)/$(APP_NAME).app"
	@echo "Installation complete!"
	@echo "Right-click any PDF in Finder > Quick Actions > Convert to Markdown"
	@echo "Launch $(APP_NAME).app from $(USER_APP_DIR) to run the background monitor"

install-system: build build-app
	@echo "Installing $(BINARY_NAME) to $(INSTALL_DIR) (requires sudo)..."
	sudo install -m 755 -o root -g wheel $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	sudo codesign --force --sign - $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Creating Quick Action workflow..."
	PDF2MD_PATH="$(INSTALL_DIR)/$(BINARY_NAME)" bash Scripts/create-workflow.sh
	@echo "Installing $(APP_NAME).app to $(SYSTEM_APP_DIR) (requires sudo)..."
	sudo rm -rf "$(SYSTEM_APP_DIR)/$(APP_NAME).app"
	sudo cp -R "$(BUILD_DIR)/$(APP_NAME).app" "$(SYSTEM_APP_DIR)/$(APP_NAME).app"
	sudo codesign --force --sign - --entitlements "$(APP_ENTITLEMENTS)" "$(SYSTEM_APP_DIR)/$(APP_NAME).app"
	@echo "Installation complete!"
	@echo "Launch $(APP_NAME).app from $(SYSTEM_APP_DIR) to run the background monitor"

uninstall:
	rm -f $(USER_INSTALL_DIR)/$(BINARY_NAME)
	sudo rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	rm -rf "$(SERVICES_DIR)/$(WORKFLOW_NAME).workflow"
	rm -rf "$(USER_APP_DIR)/$(APP_NAME).app"
	sudo rm -rf "$(SYSTEM_APP_DIR)/$(APP_NAME).app"
	@echo "Uninstalled."

clean:
	rm -rf $(BUILD_DIR)
