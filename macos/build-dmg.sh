#!/usr/bin/env bash
# =============================================================================
# Ponten — build-dmg.sh
#
# Builds a distributable .dmg disk image with drag-to-Applications installer.
#
# Usage:
#   ./build-dmg.sh           → build DMG → dist/Ponten-1.0.0.dmg
#   ./build-dmg.sh --skip-compile  → reuse existing .build/ (faster iteration)
#   ./build-dmg.sh --help    → show help
#
# Requirements: macOS 13+, Swift Command Line Tools (xcode-select --install)
# No third-party tools needed — uses only hdiutil, codesign, osascript, sips.
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
VERSION="1.2.12"
BUNDLE_ID="com.ponten.app"
MIN_MACOS="13.0"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx${MIN_MACOS}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
BUNDLE_PATH="${BUILD_DIR}/${APP_NAME}.app"
BINARY_PATH="${BUILD_DIR}/${APP_NAME}"
STAGING_DIR="${BUILD_DIR}/dmg-staging"
DIST_DIR="${SCRIPT_DIR}/dist"
DMG_NAME="Ponten-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
VOLUME_NAME="${APP_NAME} ${VERSION}"

# DMG window dimensions
DMG_WIN_W=560
DMG_WIN_H=320
# Icon positions (x, y) within the window
APP_ICON_X=160
APP_ICON_Y=160
APPS_LINK_X=400
APPS_LINK_Y=160

SOURCE_FILES=(
    "Ponten/App/PontenApp.swift"
    "Ponten/App/AppDelegate.swift"
    "Ponten/Models/SignatureManager.swift"
    "Ponten/Models/SignatureStore.swift"
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
    echo -e "${BOLD}Ponten — DMG Builder${NC}"
    echo ""
    echo "  ./build-dmg.sh                 Build .dmg from source"
    echo "  ./build-dmg.sh --skip-compile  Reuse existing .build/ (faster)"
    echo "  ./build-dmg.sh --help          Show this help"
    echo ""
    echo "Output: dist/Ponten-${VERSION}.dmg"
}

# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
    step "Checking prerequisites"
    command -v swiftc   &>/dev/null || error "swiftc not found. Run: xcode-select --install"
    command -v hdiutil  &>/dev/null || error "hdiutil not found (should be built into macOS)"
    command -v codesign &>/dev/null || error "codesign not found. Run: xcode-select --install"
    command -v python3  &>/dev/null || error "python3 not found"

    local sdk; sdk=$(xcrun --show-sdk-path 2>/dev/null) || error "SDK not found. Run: xcode-select --install"
    local ver; ver=$(sw_vers -productVersion)
    local major; major=$(echo "$ver" | cut -d. -f1)
    [[ "$major" -ge 13 ]] || error "macOS 13+ required (you have $ver)"

    success "Swift  : $(swiftc --version 2>&1 | head -1)"
    success "macOS  : $ver"
    success "SDK    : $sdk"
    success "hdiutil: $(hdiutil info | head -1 || echo 'present')"
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
    for f in "${SOURCE_FILES[@]}"; do abs_sources+=("${SCRIPT_DIR}/${f}"); done

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

    rm -rf "$BUNDLE_PATH"
    mkdir -p "${contents}/MacOS" "${contents}/Resources"

    cp "$BINARY_PATH" "${contents}/MacOS/${APP_NAME}"
    chmod +x "${contents}/MacOS/${APP_NAME}"

    if [[ -f "Ponten/Resources/AppIcon.icns" ]]; then
        cp "Ponten/Resources/AppIcon.icns" "${contents}/Resources/"
    fi
    if [[ -f "Ponten/Resources/MenuBarIconTemplate.png" ]]; then
        cp "Ponten/Resources/MenuBarIconTemplate.png" "${contents}/Resources/"
    fi
    if [[ -f "Ponten/Resources/OriginalLogo.png" ]]; then
        cp "Ponten/Resources/OriginalLogo.png" "${contents}/Resources/"
    fi

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
    <key>CFBundleIdentifier</key>           <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>           <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>        <string>1</string>
    <key>CFBundleExecutable</key>     <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>CFBundleIconFile</key>       <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key> <string>${MIN_MACOS}</string>
    <key>NSPrincipalClass</key>       <string>NSApplication</string>
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
    step "Signing .app (ad-hoc)"
    codesign --sign - --force --deep --timestamp=none "$BUNDLE_PATH"
    success "Signed .app"
}

# ── Background image ──────────────────────────────────────────────────────────
make_background() {
    local bg_path="$1"
    python3 - "$bg_path" "$DMG_WIN_W" "$DMG_WIN_H" \
        "$APP_ICON_X" "$APP_ICON_Y" "$APPS_LINK_X" "$APPS_LINK_Y" <<'PYEOF'
import sys, struct, zlib

out_path = sys.argv[1]
W, H     = int(sys.argv[2]), int(sys.argv[3])
ax, ay   = int(sys.argv[4]), int(sys.argv[5])
lx, ly   = int(sys.argv[6]), int(sys.argv[7])

def chunk(tag, data):
    crc = zlib.crc32(tag + data) & 0xffffffff
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', crc)

def clamp(v): return max(0, min(255, int(v)))

rows = b''
for y in range(H):
    rows += b'\x00'
    for x in range(W):
        t = y / H          # 0 (top) → 1 (bottom)
        
        # Background: dark blue-grey gradient
        r = clamp(22 + (1 - t) * 18)
        g = clamp(26 + (1 - t) * 18)
        b = clamp(42 + (1 - t) * 24)
        
        # Subtle horizontal centre line (visual guide)
        if abs(y - H // 2) < 1:
            r = clamp(r + 8); g = clamp(g + 8); b = clamp(b + 10)
        
        # Soft spotlight under app icon position
        for cx, cy in [(ax, ay), (lx, ly)]:
            dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            glow = max(0, 1 - dist / 80)
            r = clamp(r + glow * 20)
            g = clamp(g + glow * 22)
            b = clamp(b + glow * 35)
        
        rows += bytes([r, g, b])

compressed = zlib.compress(rows, 9)
ihdr = struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)
png  = (b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', ihdr)
        + chunk(b'IDAT', compressed)
        + chunk(b'IEND', b''))

with open(out_path, 'wb') as f:
    f.write(png)
print(f"  background: {W}x{H}px, {len(png)} bytes")
PYEOF
}

# ── DMG staging ───────────────────────────────────────────────────────────────
prepare_staging() {
    step "Preparing DMG staging area"

    rm -rf "$STAGING_DIR"
    mkdir -p "${STAGING_DIR}/.background"

    # App bundle
    cp -R "$BUNDLE_PATH" "${STAGING_DIR}/${APP_NAME}.app"

    # Symlink to /Applications (the drag target)
    ln -s /Applications "${STAGING_DIR}/Applications"

    # Background image
    info "Generating background image..."
    make_background "${STAGING_DIR}/.background/background.png"
    success "Staging ready → ${STAGING_DIR}"
}

# ── Create DMG ────────────────────────────────────────────────────────────────
create_dmg() {
    step "Creating DMG"

    mkdir -p "$DIST_DIR"
    local tmp_dmg="${BUILD_DIR}/tmp_rw.dmg"
    local volume_path="/Volumes/${VOLUME_NAME}"

    # Remove leftover mounts / files
    if [[ -d "$volume_path" ]]; then
        hdiutil detach "$volume_path" -force 2>/dev/null || true
    fi
    rm -f "$tmp_dmg" "$DMG_PATH"

    # 1. Create writable DMG from staging folder
    info "Creating writable image..."
    hdiutil create \
        -srcfolder "$STAGING_DIR" \
        -volname   "$VOLUME_NAME" \
        -fs        HFS+ \
        -fsargs    "-c c=64,a=16,b=16" \
        -format    UDRW \
        -size      80m \
        "$tmp_dmg" \
        > /dev/null

    # 2. Mount it
    info "Mounting image..."
    hdiutil attach "$tmp_dmg" \
        -mountpoint "$volume_path" \
        -nobrowse \
        -quiet

    # 3. Set Finder window appearance via AppleScript
    info "Configuring Finder window layout..."
    osascript <<APPLESCRIPT || true
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, ${DMG_WIN_W} + 200, ${DMG_WIN_H} + 120}
        
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set background picture of opts to file ".background:background.png"
        
        -- Position icons
        set position of item "${APP_NAME}.app" of container window to {${APP_ICON_X}, ${APP_ICON_Y}}
        set position of item "Applications" of container window to {${APPS_LINK_X}, ${APPS_LINK_Y}}
        
        -- Hide background folder
        set the extension hidden of item ".background" of container window to true
        
        close
        open
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

    # 4. Set volume icon (optional — uses system folder icon as fallback)
    # Give Finder time to flush metadata
    sync
    sleep 2

    # 5. Unmount
    info "Unmounting..."
    hdiutil detach "$volume_path" -quiet

    # 6. Convert to compressed, read-only UDZO
    info "Compressing to final DMG..."
    hdiutil convert "$tmp_dmg" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$DMG_PATH" \
        > /dev/null

    rm -f "$tmp_dmg"
    success "DMG → ${DMG_PATH}"

    # File size
    local size; size=$(du -sh "$DMG_PATH" | cut -f1)
    success "Size   : $size"
}

# ── Sign DMG ──────────────────────────────────────────────────────────────────
sign_dmg() {
    step "Signing DMG (ad-hoc)"
    codesign --sign - --force "$DMG_PATH"
    success "Signed DMG"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║           DMG built successfully! 🎉             ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}File:${NC}  ${DMG_PATH}"
    echo -e "  ${BOLD}Size:${NC}  $(du -sh "$DMG_PATH" | cut -f1)"
    echo ""
    echo -e "  ${BOLD}To install:${NC}"
    echo "  1. Open the .dmg file"
    echo "  2. Drag '${APP_NAME}' → Applications folder"
    echo "  3. Eject the disk image"
    echo "  4. Launch from Applications — look for 🖊 in menu bar"
    echo ""
    echo -e "  ${BOLD}To share:${NC}"
    echo "  Upload ${DMG_NAME} to GitHub Releases for users to download."
    echo ""
    # Open dist/ in Finder
    open "$DIST_DIR" 2>/dev/null || true
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    local skip_compile=false

    for arg in "$@"; do
        case "$arg" in
            --help|-h)        usage; exit 0 ;;
            --skip-compile)   skip_compile=true ;;
        esac
    done

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║    Ponten — DMG Builder  ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""

    check_prerequisites

    if [[ "$skip_compile" == false ]]; then
        compile
        bundle
        sign_app
    else
        info "Skipping compile — reusing existing .build/"
        [[ -d "$BUNDLE_PATH" ]] || error "No bundle found at ${BUNDLE_PATH}. Run without --skip-compile."
    fi

    prepare_staging
    create_dmg
    sign_dmg
    print_summary
}

main "$@"
