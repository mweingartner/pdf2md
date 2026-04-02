BINARY_NAME = pdf2md
BUILD_DIR = .build
INSTALL_DIR = /usr/local/bin
USER_INSTALL_DIR = $(HOME)/.local/bin
WORKFLOW_NAME = Convert to Markdown
SERVICES_DIR = $(HOME)/Library/Services

.PHONY: all build install uninstall clean

all: build

build:
	@mkdir -p $(BUILD_DIR)
	swiftc -O -o $(BUILD_DIR)/$(BINARY_NAME) \
		Sources/main.swift \
		Sources/PDFExtractor.swift \
		Sources/MarkdownFormatter.swift \
		Sources/TextCleaner.swift \
		-framework PDFKit \
		-framework AppKit

install: build
	@mkdir -p $(USER_INSTALL_DIR)
	@echo "Installing $(BINARY_NAME) to $(USER_INSTALL_DIR)..."
	cp $(BUILD_DIR)/$(BINARY_NAME) $(USER_INSTALL_DIR)/$(BINARY_NAME)
	chmod 755 $(USER_INSTALL_DIR)/$(BINARY_NAME)
	@# Ad-hoc code sign to satisfy Gatekeeper (Security H-2)
	codesign --force --sign - $(USER_INSTALL_DIR)/$(BINARY_NAME)
	@echo "Creating Quick Action workflow..."
	PDF2MD_PATH="$(USER_INSTALL_DIR)/$(BINARY_NAME)" bash Scripts/create-workflow.sh
	@echo "Installation complete!"
	@echo "Right-click any PDF in Finder > Quick Actions > Convert to Markdown"

install-system: build
	@echo "Installing $(BINARY_NAME) to $(INSTALL_DIR) (requires sudo)..."
	sudo install -m 755 -o root -g wheel $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	sudo codesign --force --sign - $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Creating Quick Action workflow..."
	PDF2MD_PATH="$(INSTALL_DIR)/$(BINARY_NAME)" bash Scripts/create-workflow.sh
	@echo "Installation complete!"

uninstall:
	rm -f $(USER_INSTALL_DIR)/$(BINARY_NAME)
	sudo rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	rm -rf "$(SERVICES_DIR)/$(WORKFLOW_NAME).workflow"
	@echo "Uninstalled."

clean:
	rm -rf $(BUILD_DIR)
