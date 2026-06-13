# Personal Signature — Makefile
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   make              → install (compile + bundle + sign + install)
#   make build        → compile only, output to .build/
#   make install      → compile + bundle + sign + install to ~/Applications
#   make run          → install + launch
#   make clean        → remove .build/
#   make uninstall    → remove app from ~/Applications
#   make help         → show this help
# ─────────────────────────────────────────────────────────────────────────────

APP_NAME     := Personal Signature
VERSION      := 1.0.0
BUNDLE_ID    := com.personalsignature.app
MIN_MACOS    := 13.0
ARCH         := $(shell uname -m)
TARGET       := $(ARCH)-apple-macosx$(MIN_MACOS)
SDK          := $(shell xcrun --show-sdk-path)

BUILD_DIR    := .build
BINARY       := $(BUILD_DIR)/$(APP_NAME)
BUNDLE       := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR  := $(HOME)/Applications
INSTALLED    := $(INSTALL_DIR)/$(APP_NAME).app

SOURCES := \
	PersonalSignature/App/PersonalSignatureApp.swift \
	PersonalSignature/App/AppDelegate.swift \
	PersonalSignature/Models/SignatureManager.swift \
	PersonalSignature/Views/MenuBarView.swift \
	PersonalSignature/Views/Components.swift \
	PersonalSignature/Utilities/EventMonitor.swift

SWIFTFLAGS := \
	-sdk $(SDK) \
	-target $(TARGET) \
	-parse-as-library \
	-O \
	-whole-module-optimization \
	-framework AppKit \
	-framework SwiftUI \
	-framework ServiceManagement \
	-framework UniformTypeIdentifiers

.DEFAULT_GOAL := install

# ─── Targets ─────────────────────────────────────────────────────────────────

.PHONY: help build bundle sign install run clean uninstall

help:
	@echo ""
	@echo "Personal Signature — Build & Install"
	@echo "─────────────────────────────────────"
	@echo "  make           Install the app (build + bundle + sign + install)"
	@echo "  make build     Compile Swift sources only"
	@echo "  make run       Install and launch the app"
	@echo "  make clean     Remove .build/ directory"
	@echo "  make uninstall Remove app from ~/Applications"
	@echo ""

## 1. Compile
build: $(BUILD_DIR)
	@echo "▶ Compiling $(APP_NAME) v$(VERSION) for $(TARGET)..."
	@swiftc $(SWIFTFLAGS) -o "$(BINARY)" $(SOURCES)
	@echo "✅ Compiled → $(BINARY)"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

## 2. Bundle
bundle: build
	@echo "▶ Creating .app bundle..."
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	@cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@chmod +x "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@[ -f "PersonalSignature/Resources/AppIcon.icns" ] && \
		cp "PersonalSignature/Resources/AppIcon.icns" "$(BUNDLE)/Contents/Resources/" || true
	@# Generate Info.plist inline
	@/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" \
		"$(BUNDLE)/Contents/Info.plist" 2>/dev/null || true
	@/usr/bin/plutil -convert xml1 - -o "$(BUNDLE)/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key><true/>
    <key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>
    <key>CFBundleName</key><string>$(APP_NAME)</string>
    <key>CFBundleDisplayName</key><string>$(APP_NAME)</string>
    <key>CFBundleShortVersionString</key><string>$(VERSION)</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleExecutable</key><string>$(APP_NAME)</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>$(MIN_MACOS)</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF
	@cp PersonalSignature/Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@echo "✅ Bundle → $(BUNDLE)"

## 3. Sign (ad-hoc)
sign: bundle
	@echo "▶ Signing (ad-hoc)..."
	@codesign --sign - --force --deep --timestamp=none "$(BUNDLE)" 2>&1 | grep -v "^$$" || true
	@echo "✅ Signed"

## 4. Install
install: sign
	@echo "▶ Installing to $(INSTALL_DIR)..."
	@mkdir -p "$(INSTALL_DIR)"
	@-pkill -x "Personal Signature" 2>/dev/null; sleep 0.3; true
	@rm -rf "$(INSTALLED)"
	@cp -R "$(BUNDLE)" "$(INSTALLED)"
	@xattr -cr "$(INSTALLED)" 2>/dev/null || true
	@echo "✅ Installed → $(INSTALLED)"
	@echo ""
	@echo "Run 'make run' or 'open ~/Applications/Personal\ Signature.app' to launch."

## 5. Run
run: install
	@echo "▶ Launching $(APP_NAME)..."
	@open "$(INSTALLED)"
	@echo "✅ Look for the 🖊 icon in your menu bar!"
	@echo "   Global shortcut: ⌥⌘S to copy signature from anywhere."

## 6. Clean
clean:
	@rm -rf "$(BUILD_DIR)"
	@echo "✅ Cleaned .build/"

## 7. Uninstall
uninstall:
	@-pkill -x "Personal Signature" 2>/dev/null; sleep 0.3; true
	@rm -rf "$(INSTALLED)"
	@echo "✅ Uninstalled $(APP_NAME)"
