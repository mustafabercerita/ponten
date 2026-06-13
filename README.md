# Personal Signature 🖊️

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

**Personal Signature eliminates steps 1–3.** Your signature lives in the menu bar, one click away.

---

## Demo Flow

```
Install app → 🖊 icon appears in menu bar → click icon
→ Add Signature (choose PNG or drag & drop)
→ preview thumbnail shows in popover
→ click [Sign] — or press ⌥⌘S from anywhere
→ "Signature copied to clipboard ✓"
→ ⌘V in Word / Google Docs / PDF / email → done.
```

---

## Features (v1.0)

| Feature | Description |
|---|---|
| **Menu bar icon** | Lives quietly in the macOS menu bar — no Dock icon |
| **Add Signature** | Pick a PNG / JPEG / TIFF via file picker |
| **Drag & Drop** | Drag an image file directly onto the popover |
| **Live preview** | Thumbnail of the active signature in the popover |
| **One-click Sign** | Copies signature image to clipboard instantly |
| **Global hotkey ⌥⌘S** | Copy signature without even opening the popover |
| **Change Signature** | Swap active signature at any time |
| **Remove Signature** | Delete saved signature with confirmation |
| **Launch at Login** | Toggle auto-start via `SMAppService` |
| **Toast feedback** | "Signature copied to clipboard ✓" animated notification |
| **About panel** | Version info, GitHub link, keyboard shortcut hint |
| **Persistent storage** | Signature survives app restarts (stored locally) |
| **Zero dependencies** | Pure Swift / SwiftUI / AppKit — no Electron, no backend |

---

## Requirements

- **macOS 13.0 Ventura** or later
- **Xcode 15.0** or later
- Apple Developer account (free tier is enough for local builds)

---

## Getting Started

### Option A — One-command install (no Xcode GUI needed) ⚡

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

### Option B — Build with Xcode

1. Clone the repo and open `PersonalSignature.xcodeproj` in Xcode 15+
2. Select the **PersonalSignature** target → **Signing & Capabilities** → set your Team
3. Press **⌘R**. Look for the **🖊 icon** in your menu bar.

> `LSUIElement = YES` — the app intentionally does **not** appear in the Dock or ⌘Tab.

### First use

1. Click the 🖊 menu bar icon
2. Click **Add Signature** (or drag a PNG file onto the popover)
3. Preview appears immediately
4. Click **Sign** (or press **⌥⌘S** from anywhere) to copy to clipboard
5. **⌘V** anywhere — done

---

## Keyboard Shortcut

| Shortcut | Action |
|---|---|
| **⌥⌘S** | Copy signature to clipboard (global — works without opening popover) |
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
│   │   └── EventMonitor.swift           Outside-click detection
│   │
│   └── Resources/
│       ├── Info.plist                   LSUIElement, bundle metadata
│       └── Assets.xcassets/            AppIcon + AccentColor
│
├── PersonalSignatureTests/
│   └── SignatureManagerTests.swift      7 unit tests
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

Tests cover:
- `testInitialStateHasNoSignature`
- `testSaveValidPNGLoadsImage`
- `testSaveInvalidPathThrowsError`
- `testDeleteSignatureClearsImage`
- `testCopyToClipboardReturnsFalseWithNoSignature`
- `testCopyToClipboardReturnsTrueWithSignature`
- `testToastMessageClearsAfterDelay`
- `testReplacingSignatureUpdatesImage`

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full technical walkthrough.

**TL;DR:**

```
AppDelegate
  ├─ NSStatusItem → NSPopover → NSHostingController<MenuBarView>
  │                                 └─ SignatureManager (@EnvironmentObject)
  │                                       ├─ @Published signatureImage: NSImage?
  │                                       ├─ @Published toastMessage: String?
  │                                       ├─ @Published launchAtLogin: Bool
  │                                       ├─ saveSignature(from:)  → disk
  │                                       ├─ copySignatureToClipboard() → NSPasteboard
  │                                       ├─ deleteSignature()
  │                                       └─ setLaunchAtLogin(_:) → SMAppService
  └─ Global hotkey monitor (⌥⌘S) → copySignatureToClipboard()
```

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

## MVP Limitations

- **One signature slot** — no multi-profile switching yet
- **No drawing canvas** — must supply an existing image file
- **Raster only** — no SVG support

---

## Roadmap

- [ ] Multiple signature profiles with quick-switch
- [ ] Built-in drawing canvas (trackpad / Apple Pencil via Sidecar)
- [ ] Background removal / transparent PNG enforcement
- [ ] Drag & drop onto any application icon in Dock
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
