<div align="center">
<img src="Logo/Personal%20Signature%20Logo.png" width="150" height="150" alt="Logo">
<h1>Personal Signature</h1>
</div>

> A lightweight macOS menu bar app that puts your digital signature one click away.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![Open Source](https://img.shields.io/badge/Open-Source-brightgreen)
[![CI](https://github.com/mustafabercerita/personal-signature/actions/workflows/ci.yml/badge.svg)](https://github.com/mustafabercerita/personal-signature/actions/workflows/ci.yml)

---

## The Problem

Every time you need to sign a document — Word, Excel, Google Docs, a PDF editor, an email — you have to:

1. Open Finder
2. Navigate to your signature file
3. Copy the image
4. Paste it into the document

**Personal Signature eliminates steps 1–3.** Your signature lives in the menu bar, one click away. With the new Auto-Paste feature, it even eliminates step 4!

---

## Demo Flow

```
Install app → 🖊 icon appears in menu bar → click icon
→ Add Signature (choose PNG or drag & drop)
→ preview thumbnail shows in popover
→ press ⌥⌘S from anywhere
→ "Signature copied & pasted ✓"
→ Signature is automatically pasted into your active document!
```

---

## Features (v1.0)

| Feature | Description |
|---|---|
| **Menu-bar-only architecture** | Lives quietly in the macOS menu bar — no Dock icon |
| **Global hotkey ⌥⌘S** | Copy and paste your signature without even opening the popover |
| **Auto-Paste Functionality** | Automatically pastes the signature into your active application |
| **Accessibility Permissions** | Seamlessly prompts for and handles accessibility access needed for auto-paste |
| **Native Auto-Updater** | Built-in GitHub Releases auto-updater to keep you on the latest version |
| **Drag & Drop** | Drag an image file directly onto the popover to set your signature |
| **Live preview** | Thumbnail of the active signature in the popover |
| **One-click Sign** | Copies signature image to clipboard instantly |
| **Change Signature** | Swap active signature at any time |
| **Remove Signature** | Delete saved signature with confirmation |
| **Launch at Login** | Toggle auto-start via `SMAppService` |
| **Persistent storage** | Signature survives app restarts (stored locally) |
| **Zero third-party dependencies** | Pure Swift / SwiftUI / AppKit — no Sparkle, no Electron, no backend |

---

## Requirements

- **macOS 13.0 Ventura** or later
- **Xcode 15.0** or later
- Apple Developer account (free tier is enough for local builds)

---

## Getting Started

### Option A — Download App (.dmg) 📦

This is the easiest way to install.

1. Go to the [Releases](https://github.com/mustafabercerita/personal-signature/releases) page.
2. Download `PersonalSignature-1.0.0.dmg`.
3. Open the downloaded file and drag the **Personal Signature** icon into the **Applications** folder.
4. Launch from your Applications folder.

> **Note**: Because this is an open-source app signed ad-hoc, you may need to right-click the app and choose **Open** the first time you run it to bypass macOS Gatekeeper.

---

### Option B — One-command CLI install ⚡

```bash
git clone https://github.com/mustafabercerita/personal-signature.git
cd personal-signature
./install.sh
```

That's it. The script will:
1. Check prerequisites (Swift compiler, macOS 13+)
2. Compile all Swift sources
3. Package into a `.app` bundle
4. Sign with an ad-hoc signature
5. Install to `~/Applications/`
6. Launch the app automatically

> Look for the **🖊 icon** in your menu bar after it launches.

#### Other install commands

```bash
./install.sh --build      # Compile only, don't install
./install.sh --uninstall  # Remove the app
./install.sh --help       # Show all options
```

#### Or with Make

```bash
make          # build + install
make run      # build + install + launch
make clean    # remove build artifacts
make uninstall
```

---

### Option C — Build with Xcode

1. Clone the repo and open `PersonalSignature.xcodeproj` in Xcode 15+
2. Select the **PersonalSignature** target → **Signing & Capabilities** → set your Team
3. Press **⌘R**. Look for the **🖊 icon** in your menu bar.

> `LSUIElement = YES` — the app intentionally does **not** appear in the Dock or ⌘Tab.

### First use

1. Click the 🖊 menu bar icon
2. Click **Add Signature** (or drag a PNG file onto the popover)
3. Preview appears immediately
4. Click **Sign** (or press **⌥⌘S** from anywhere) to copy to clipboard
5. The app will prompt you for Accessibility Permissions the first time you use Auto-Paste.
6. Once granted, **⌥⌘S** will automatically copy AND paste the signature wherever your text cursor is active.

---

## Keyboard Shortcut

| Shortcut | Action |
|---|---|
| **⌥⌘S** | Copy & Paste signature to active application (global — works without opening popover) |
| **⌘Q** | Quit the app |
| **Return** | Sign (when popover is open) |
| **Escape** | Close popover |

---

## Project Structure

```
Personal Signature/
├── .github/
│   └── workflows/
│       └── ci.yml                   # GitHub Actions CI (build + test + archive)
│
├── PersonalSignature.xcodeproj/
│   └── project.pbxproj
│
├── PersonalSignature/
│   ├── App/
│   │   ├── PersonalSignatureApp.swift   @main entry point
│   │   └── AppDelegate.swift            NSStatusItem + NSPopover + global hotkey
│   │
│   ├── Models/
│   │   └── SignatureManager.swift       All business logic + persistence + clipboard
│   │
│   ├── Views/
│   │   ├── MenuBarView.swift            Root SwiftUI popover view
│   │   └── Components.swift             PrimaryButtonStyle, SecondaryButtonStyle, ToastView
│   │
│   ├── Utilities/
│   │   ├── EventMonitor.swift           Outside-click detection
│   │   ├── AutoUpdater.swift            Native GitHub Releases updater
│   │   └── AccessibilityPermissions.swift Accessibility check & prompt
│   │
│   └── Resources/
│       ├── Info.plist                   LSUIElement, bundle metadata
│       └── Assets.xcassets/            AppIcon + AccentColor
│
├── PersonalSignatureTests/
│   └── SignatureManagerTests.swift      Unit tests
│
├── README.md
├── ARCHITECTURE.md
├── CHANGELOG.md
├── LICENSE (MIT)
└── .gitignore
```

---

## Running Tests

In Xcode: **⌘U** or **Product → Test**

Or via CLI:
```bash
xcodebuild -project PersonalSignature.xcodeproj -scheme PersonalSignature -destination 'platform=macOS' test
```

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full technical walkthrough.

---

## Build for Distribution

### Non-App Store (Developer ID)

1. **Product → Archive** in Xcode
2. **Distribute App → Developer ID → Export**
3. Optionally notarize: `xcrun notarytool submit ...`

### CI / Automated builds

Every push to `main` triggers a GitHub Actions workflow that:
- Builds Debug
- Runs all unit tests
- Archives Release
- Uploads `.xcarchive` as artifact (14-day retention)

---

## Roadmap & Completed Features

We've recently crossed off several major milestones from our original roadmap! Here's the current status of the project:

### ✅ Completed
- [x] **Multiple signature profiles:** Save and quickly switch between different signatures directly from the popover grid.
- [x] **Background removal:** Automatically drops white backgrounds from JPEG/PNG images using native CoreImage filters so your signature is clean and transparent.
- [x] **Auto-Paste:** Uses macOS Accessibility APIs to automatically paste your signature into the active document right after copying.
- [x] **Global Shortcut Customization:** Record your own custom global hotkey to trigger the app from anywhere.
- [x] **Drag & Drop Out:** Drag the signature from the popover directly into your target app.
- [x] **Native Auto-Updater:** Replaced heavy Sparkle framework with a lightweight, native SwiftUI GitHub release checker.

### 🚀 Upcoming Features
- [ ] Built-in drawing canvas (trackpad / Apple Pencil via Sidecar)
- [ ] App Store release
- [ ] Swift Package Manager support for modularization

---

## Contributing

Pull requests are welcome! Please open an issue first to discuss major changes.

```bash
git checkout -b feature/my-feature
git commit -m 'feat: add my feature'
git push origin feature/my-feature
# Open Pull Request → CI runs automatically
```

---

## License

MIT License — see [LICENSE](LICENSE).

---

*Made with ❤️ to save you those extra clicks, every single day.*
