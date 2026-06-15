#!/usr/bin/env bash
# =============================================================================
# Ponten — install.sh
# Compiles the app from source and installs it to ~/Applications
#
# Usage:
#   ./install.sh              → build, bundle, sign, install & launch
#   ./install.sh --build      → compile only (output to .build/)
#   ./install.sh --uninstall  → remove the app
#   ./install.sh --help       → show help
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}▶${NC}  $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠️ ${NC} $*"; }
error()   { echo -e "${RED}❌${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }

# ── Config ────────────────────────────────────────────────────────────────────
APP_NAME="Ponten"
BUNDLE_ID="com.ponten.app"
VERSION="1.2.9"
MIN_MACOS="13.0"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx${MIN_MACOS}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
BUNDLE_PATH="${BUILD_DIR}/${APP_NAME}.app"
BINARY_PATH="${BUILD_DIR}/${APP_NAME}"
INSTALL_DIR="${HOME}/Applications"
INSTALLED_PATH="${INSTALL_DIR}/${APP_NAME}.app"

SOURCE_FILES=(
    "Ponten/App/PontenApp.swift"
    "Ponten/App/AppDelegate.swift"
    "Ponten/Models/SignatureManager.swift"
    "Ponten/Views/MenuBarView.swift"
    "Ponten/Views/HeaderView.swift"
    "Ponten/Views/SignatureActiveView.swift"
    "Ponten/Views/EmptyStateView.swift"
    "Ponten/Views/FooterView.swift"
    "Ponten/Views/AboutView.swift"
    "Ponten/Views/Components.swift"
    "Ponten/Utilities/EventMonitor.swift"
    "Ponten/Utilities/GlobalShortcutManager.swift"
    "Ponten/Views/DrawingView.swift"
    "Ponten/Models/ImageProcessor.swift"
    "Ponten/Views/ImageEditorView.swift"
)

# ── Help ──────────────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "${BOLD}Ponten — CLI Installer${NC}"
    echo ""
    echo "  ./install.sh             Build & install the app"
    echo "  ./install.sh --build     Compile only (no install)"
    echo "  ./install.sh --uninstall Remove the app"
    echo "  ./install.sh --help      Show this help"
    echo ""
    echo "After install, look for the 🖊 icon in your menu bar."
    echo "Global shortcut: ⌥⌘S — copy signature from anywhere."
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
uninstall() {
    step "Uninstalling ${APP_NAME}"
    pkill -x "Ponten" 2>/dev/null && sleep 0.5 || true
    if [[ -d "$INSTALLED_PATH" ]]; then
        rm -rf "$INSTALLED_PATH"
        success "Removed: ${INSTALLED_PATH}"
    else
        warn "App not found at ${INSTALLED_PATH}"
    fi
}

# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
    step "Checking prerequisites"

    command -v swiftc &>/dev/null || \
        error "swiftc not found. Install Command Line Tools:\n  xcode-select --install"
    success "Swift: $(swiftc --version 2>&1 | head -1)"

    local ver major
    ver=$(sw_vers -productVersion)
    major=$(echo "$ver" | cut -d. -f1)
    [[ "$major" -ge 13 ]] || error "macOS 13+ required (you have $ver)"
    success "macOS: $ver ✓"

    local sdk
    sdk=$(xcrun --show-sdk-path 2>/dev/null) || error "SDK not found. Run: xcode-select --install"
    success "SDK: $sdk"
}

# ── Compile ───────────────────────────────────────────────────────────────────
compile() {
    step "Compiling ${APP_NAME} v${VERSION}"

    local sdk; sdk=$(xcrun --show-sdk-path)
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    info "Target : $TARGET"
    info "Sources: ${#SOURCE_FILES[@]} files"

    local abs_sources=()
    for f in "${SOURCE_FILES[@]}"; do
        abs_sources+=("${SCRIPT_DIR}/${f}")
    done

    swiftc \
        -sdk "$sdk" \
        -target "$TARGET" \
        -parse-as-library \
        -O \
        -whole-module-optimization \
        -framework AppKit \
        -framework SwiftUI \
        -framework ServiceManagement \
        -framework UniformTypeIdentifiers \
        -o "$BINARY_PATH" \
        "${abs_sources[@]}"

    success "Binary → ${BINARY_PATH}"
}

# ── Bundle ────────────────────────────────────────────────────────────────────
bundle() {
    step "Building .app bundle"

    local contents="${BUNDLE_PATH}/Contents"
    local macos_dir="${contents}/MacOS"

    rm -rf "$BUNDLE_PATH"
    mkdir -p "$macos_dir" "${contents}/Resources"

    cp "$BINARY_PATH" "${macos_dir}/${APP_NAME}"
    chmod +x "${macos_dir}/${APP_NAME}"

    # Copy AppIcon.icns and MenuBarIcon
    if [[ -f "Ponten/Resources/AppIcon.icns" ]]; then
        cp "Ponten/Resources/AppIcon.icns" "${contents}/Resources/"
    fi
    if [[ -f "Ponten/Resources/MenuBarIconTemplate.png" ]]; then
        cp "Ponten/Resources/MenuBarIconTemplate.png" "${contents}/Resources/"
    fi
    if [[ -f "Ponten/Resources/OriginalLogo.png" ]]; then
        cp "Ponten/Resources/OriginalLogo.png" "${contents}/Resources/"
    fi

    # Write Info.plist
    cat > "${contents}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>SUFeedURL</key>
    <string>https://example.com/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>placeholder</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Ponten needs access to read your signature file.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Ponten needs access to read your signature file.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Ponten needs access to read your signature file.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 Ponten Contributors. MIT License.</string>
</dict>
</plist>
PLIST

    success "Bundle → ${BUNDLE_PATH}"
}

# ── Sign (ad-hoc) ─────────────────────────────────────────────────────────────
sign_app() {
    step "Signing (ad-hoc)"
    codesign --sign - --force --deep --timestamp=none "$BUNDLE_PATH" || \
        warn "Code signing failed — app may trigger Gatekeeper warning"
    success "Signed"
}

# ── Install ───────────────────────────────────────────────────────────────────
install_app() {
    step "Installing to ~/Applications"

    # Quit existing instance gracefully
    pkill -x "Ponten" 2>/dev/null && sleep 0.5 || true

    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALLED_PATH"
    cp -R "$BUNDLE_PATH" "$INSTALLED_PATH"

    # Strip quarantine so macOS doesn't block a self-signed app
    xattr -cr "$INSTALLED_PATH" 2>/dev/null || true

    success "Installed → ${INSTALLED_PATH}"
}

# ── Launch ────────────────────────────────────────────────────────────────────
launch_app() {
    step "Launching ${APP_NAME}"
    open "$INSTALLED_PATH"
    success "App is running — look for the 🖊 icon in your menu bar!"
    echo ""
    echo -e "  ${BOLD}Quick start:${NC}"
    echo "  1. Click the 🖊 icon in the menu bar"
    echo "  2. Click 'Add Signature' and choose a PNG file"
    echo "  3. Click 'Sign' to copy your signature to clipboard"
    echo "  4. ⌘V anywhere to paste"
    echo ""
    echo -e "  ${BOLD}Global shortcut:${NC} ⌥⌘S — copy without opening the popover"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║     Ponten Installer     ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""

    case "${1:-}" in
        --help|-h)   usage;      exit 0 ;;
        --uninstall) uninstall;  exit 0 ;;
        --build)
            check_prerequisites
            compile
            bundle
            success "Build complete. Run './install.sh' to install."
            exit 0
            ;;
    esac

    # Full install flow
    check_prerequisites
    compile
    bundle
    sign_app
    install_app
    launch_app

    echo ""
    echo -e "${GREEN}${BOLD}🎉 All done!${NC}"
    echo ""
}

main "$@"
