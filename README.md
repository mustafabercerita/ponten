<div align="center">
<img src="Logo/Ponten%20Logo.png" width="150" height="150" alt="Logo">
<h1>Ponten</h1>
</div>

> A lightweight cross-platform (macOS & Windows) system tray app that puts your digital signature one click away.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple)
![Windows 10+](https://img.shields.io/badge/Windows-10%2B-blue?logo=windows)
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![.NET 8.0](https://img.shields.io/badge/.NET-8.0-purple?logo=dotnet)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![Open Source](https://img.shields.io/badge/Open-Source-brightgreen)
[![CI](https://github.com/mustafabercerita/ponten/actions/workflows/ci.yml/badge.svg)](https://github.com/mustafabercerita/ponten/actions/workflows/ci.yml)

---

## The Problem

Every time you need to sign a document — Word, Excel, Google Docs, a PDF editor, an email — you have to:

1. Open Finder / File Explorer
2. Navigate to your signature file
3. Copy the image
4. Paste it into the document

**Ponten eliminates steps 1–3.** Your signature lives in the menu bar, one click away. With the new Auto-Paste feature, it even eliminates step 4!

---

## Demo Flow

```
Install app → 🖊 icon appears in menu bar / system tray → click icon
→ Add Signature (choose PNG, drag & drop, or draw)
→ preview thumbnail shows in popover
→ press ⌥⌘S (Mac) or Ctrl+Alt+S (Win) from anywhere
→ "Signature copied & pasted ✓"
→ Signature is automatically pasted into your active document!
```

---

## Features

| Feature | Description |
|---|---|
| **Cross-Platform** | Native apps built for both macOS and Windows. |
| **System-Tray Architecture** | Lives quietly in the macOS menu bar or Windows system tray — no taskbar clutter. |
| **Global hotkey** | Copy and paste your signature without even opening the popover (⌥⌘S on Mac, Ctrl+Alt+S on Win). |
| **Auto-Paste Functionality** | Automatically pastes the signature into your active application! |
| **Native Auto-Updater** | Built-in GitHub Releases auto-updater to keep you on the latest version seamlessly. |
| **Drag & Drop** | Drag an image file directly onto the popover to set your signature. |
| **Live Preview & Pen Tools** | Adjust stroke thickness visually using native morphology techniques. |
| **Background Removal** | Automatically drops white backgrounds from JPEG/PNG images so your signature is clean and transparent. |
| **Built-in Drawing Canvas** | Draw your signature natively using your trackpad, mouse, or Apple Pencil! |
| **Multiple Signatures** | Save and quickly switch between different signatures directly from the popover grid. |
| **Native Performance** | Built with native Swift/AppKit and C#/WPF — zero Electron bloat. |

---

## Requirements

**For macOS:**
- **macOS 13.0 Ventura** or later
- **Xcode 15.0** or later
- Apple Developer account (free tier is enough for local builds)

**For Windows:**
- **Windows 10** or later
- **.NET 8.0 SDK** (for local builds)

---

## Getting Started

### Option A — Download App 📦

This is the easiest way to install.

<div align="center">
  <a href="https://github.com/mustafabercerita/ponten/releases">
    <img src="https://img.shields.io/badge/Download_for_macOS-.dmg-blue?style=for-the-badge&logo=apple" alt="Download macOS" />
  </a>
  &nbsp;
  <a href="https://github.com/mustafabercerita/ponten/releases">
    <img src="https://img.shields.io/badge/Download_for_Windows-.exe-blue?style=for-the-badge&logo=windows" alt="Download Windows" />
  </a>
</div>
<br>

1. Go to the [Releases](https://github.com/mustafabercerita/ponten/releases) page.
2. Download `Ponten-1.2.9.dmg` (for Mac) or `Ponten-Setup-1.2.9.exe` (for Windows installer).
3. **Mac**: Open the downloaded file and drag the **Ponten** icon into the **Applications** folder.
4. **Windows**: Run `Ponten-Setup-1.2.9.exe` to install the app. It will create a Start Menu shortcut, register the uninstaller, and quietly launch in your System Tray. *(A portable `.exe` is also available if you prefer no installation).*

> **Note for Mac users**: Because this is an open-source app signed ad-hoc, you may need to right-click the app and choose **Open** the first time you run it to bypass macOS Gatekeeper.

---

### Option B — One-command CLI install ⚡ (macOS)

```bash
git clone https://github.com/mustafabercerita/ponten.git
cd ponten/macos
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

---

### Option C — Build with Xcode

1. Clone the repo and open `macos/Ponten.xcodeproj` in Xcode 15+
2. Select the **Ponten** target → **Signing & Capabilities** → set your Team
3. Press **⌘R**. Look for the **🖊 icon** in your menu bar.

> `LSUIElement = YES` — the app intentionally does **not** appear in the Dock or ⌘Tab.

---

### Option D — Build with .NET CLI (Windows)

1. Clone the repo and navigate to `windows/`.
2. Run `dotnet build Ponten.sln -c Release`.
3. Launch `PontenWPF.exe` from `windows/PontenWPF/bin/Release/net8.0-windows/win-x64/`.

---

## Keyboard Shortcut

| Shortcut | Action |
|---|---|
| **⌥⌘S** / **Ctrl+Alt+S** | Copy & Paste signature to active application (global — works without opening popover) |
| **⌘Q** / **Alt+F4** | Quit the app |
| **Return** | Sign (when popover is open) |
| **Escape** | Close popover |

---

## Project Structure

```
Ponten/
├── .github/
│   └── workflows/
│       └── ci.yml                   # GitHub Actions CI for multi-platform
│
├── macos/                           # macOS App (Swift / SwiftUI / AppKit)
│   ├── Ponten.xcodeproj/
│   ├── Ponten/
│   │   ├── App/                     # Entry point & AppDelegate
│   │   ├── Models/                  # Business logic & ImageProcessor
│   │   ├── Views/                   # SwiftUI UI components
│   │   └── Resources/               # Assets, Plist
│   ├── install.sh                   # macOS CLI installer
│   └── build-dmg.sh                 # macOS DMG builder
│
├── windows/                         # Windows App (C# / WPF / .NET 8)
│   ├── Ponten.sln
│   ├── PontenWPF/
│   │   ├── App.xaml                 # Entry point
│   │   ├── MainWindow.xaml          # UI & Tray popup logic
│   │   ├── SignatureManager.cs      # Core business & Win32 logic
│   │   └── ImageEditorWindow.xaml   # Windows image editing & pen tools
│   └── build.ps1                    # Windows build script (Upcoming)
│
├── README.md
├── ARCHITECTURE.md
├── CHANGELOG.md
└── LICENSE (MIT)
```

---

## Running Tests

**macOS (via CLI):**
```bash
cd macos
xcodebuild -project Ponten.xcodeproj -scheme Ponten -destination 'platform=macOS' test
```

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full technical walkthrough.

---

## Build for Distribution

### CI / Automated builds

Every push to tags matching `v*` triggers a GitHub Actions workflow that:
- Builds macOS DMG locally and runs tests.
- Builds Windows `.exe` using `.NET 8` as a single self-contained file.
- Publishes the assets automatically to GitHub Releases.

---

## Roadmap & Completed Features

We've recently crossed off several major milestones from our original roadmap! Here's the current status of the project:

### ✅ Completed
- [x] **Windows Version:** Native Windows port built with C# and WPF.
- [x] **Pen Tools & Thickness Adjustments:** Increase ink boldness globally through advanced morphology logic.
- [x] **Built-in Drawing Canvas:** Draw your signature natively using your trackpad, mouse, or Apple Pencil (via Sidecar) right inside the app!
- [x] **Multiple signature profiles:** Save and quickly switch between different signatures directly from the popover grid.
- [x] **Background removal:** Automatically drops white backgrounds from JPEG/PNG images using native CoreImage/System.Drawing filters so your signature is clean and transparent.
- [x] **Auto-Paste:** Uses macOS Accessibility APIs and Win32 APIs to automatically paste your signature into the active document right after copying.
- [x] **Drag & Drop Out:** Drag the signature from the popover directly into your target app.
- [x] **Native Auto-Updater:** Replaced heavy Sparkle framework with a lightweight, native SwiftUI GitHub release checker.

### 🚀 Upcoming Features
- [ ] Mac App Store & Microsoft Store release
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
