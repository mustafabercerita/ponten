# Ponten — Makefile
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

APP_NAME     := Ponten
VERSION      := 1.2.0
BUNDLE_ID    := com.personalsignature.app
MIN_MACOS    := 13.0
ARCH         := $(shell uname -m)
TARGET       := $(ARCH)-apple-macosx$(MIN_MACOS)
SDK          := $(shell xcrun --show-sdk-path)

BUILD_DIR    := .build
INSTALL_DIR  := $(HOME)/Applications
INSTALLED    := $(INSTALL_DIR)/$(APP_NAME).app

.DEFAULT_GOAL := install

# ─── Targets ─────────────────────────────────────────────────────────────────

.PHONY: help build bundle sign install run clean uninstall

help:
	@echo ""
	@echo "Ponten — Build & Install"
	@echo "─────────────────────────────────────"
	@echo "  make           Install the app (build + bundle + sign + install)"
	@echo "  make build     Compile Swift sources only"
	@echo "  make run       Install and launch the app"
	@echo "  make clean     Remove .build/ directory"
	@echo "  make uninstall Remove app from ~/Applications"
	@echo ""

## 1. Compile
build:
	@echo "▶ Compiling $(APP_NAME) v$(VERSION)..."
	@swift build -c release --arch arm64 --arch x86_64
	@echo "✅ Compiled"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

## 2. Bundle
bundle: build
	@echo "▶ Creating .app bundle..."
	$(eval BUNDLE := $(BUILD_DIR)/$(APP_NAME).app)
	$(eval BIN_PATH := $(shell swift build -c release --arch arm64 --arch x86_64 --show-bin-path))
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	@cp "$(BIN_PATH)/PontenApp" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@chmod +x "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	
	@# Copy Sparkle.framework if it exists in the build output
	@[ -d "$(BIN_PATH)/Sparkle.framework" ] && \
		mkdir -p "$(BUNDLE)/Contents/Frameworks" && \
		cp -R "$(BIN_PATH)/Sparkle.framework" "$(BUNDLE)/Contents/Frameworks/" || true

	@[ -f "Ponten/Resources/AppIcon.icns" ] && \
		cp "Ponten/Resources/AppIcon.icns" "$(BUNDLE)/Contents/Resources/" || true
	@[ -f "Ponten/Resources/MenuBarIconTemplate.png" ] && \
		cp "Ponten/Resources/MenuBarIconTemplate.png" "$(BUNDLE)/Contents/Resources/" || true
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
	@cp Ponten/Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@echo "✅ Bundle → $(BUNDLE)"

## 3. Sign (ad-hoc)
sign: bundle
	@echo "▶ Signing frameworks and app (ad-hoc)..."
	$(eval BUNDLE := $(BUILD_DIR)/$(APP_NAME).app)
	@[ -d "$(BUNDLE)/Contents/Frameworks/Sparkle.framework" ] && \
		codesign --sign - --force --deep --timestamp=none "$(BUNDLE)/Contents/Frameworks/Sparkle.framework" 2>&1 | grep -v "^$$" || true
	@codesign --sign - --force --deep --timestamp=none "$(BUNDLE)" 2>&1 | grep -v "^$$" || true
	@echo "✅ Signed"

## 4. Install
install: sign
	@echo "▶ Installing to $(INSTALL_DIR)..."
	$(eval BUNDLE := $(BUILD_DIR)/$(APP_NAME).app)
	@mkdir -p "$(INSTALL_DIR)"
	@-pkill -x "Ponten" 2>/dev/null; sleep 0.3; true
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
	@-pkill -x "Ponten" 2>/dev/null; sleep 0.3; true
	@rm -rf "$(INSTALLED)"
	@echo "✅ Uninstalled $(APP_NAME)"
