# Changelog

All notable changes to **Ponten** will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- **macOS E2E test suite** — 5 UI tests (XCTest + Accessibility) in `PontenE2ETests`
- **Windows E2E test suite** — 5 UI tests (FlaUI + xUnit) in `PontenWPF.E2E.Tests`
- **E2E mode** — `--e2e` flag, `PONTEN_E2E=1`, and `PONTEN_DATA_DIR` for isolated test data (macOS + Windows)
- **CI E2E** — macOS `xcodebuild test` and Windows `dotnet test Ponten.sln -c Release` run unit + E2E

### Changed
- **SignatureStore extraction** — macOS persistence moved out of `SignatureManager` into dedicated `SignatureStore`
- **ImageProcessor extensions** — image-processing helpers consolidated in `ImageProcessor.swift`
- **Windows rename** — `SignatureManager.cs` renamed to `ImageProcessor.cs` for clarity
- **Test infrastructure** — dependency injection for storage layer; flaky tests stabilized (11 macOS unit + 5 macOS E2E + 12 Windows unit + 5 Windows E2E)
- **Documentation refresh** — README, ARCHITECTURE, CHANGELOG, DEVELOPMENT, and agent guides updated (now includes E2E testing)

---

## [1.2.12] — 2026-06-15

### Added
- **Windows installer** — Inno Setup script (`installer.iss`) with Start Menu shortcut and uninstaller
- **Windows feature parity** — draw signature canvas and global shortcut (Ctrl+Alt+S)
- **macOS right-click Quit** — Quit option on status-item context menu
- **Unit tests** — comprehensive macOS (11) and Windows (7 at release; suite later expanded to 12) test suites

### Fixed
- **Windows tray icon** — reliable registration via H.NotifyIcon.Wpf `ForceCreate()` and icon fallback
- **Windows QA audit** — GDI memory leaks, DPI scaling, thread-safe logging, clipboard robustness
- **Windows auto-paste** — modifier-key release and focus restoration
- **CI / releases** — DMG builder fixes, `gh-release` permissions, publish path for test project
- **macOS popover** — no longer closes while the file-picker dialog is open

### Changed
- **Windows UI overhaul** — popover layout aligned with macOS design; file-saving bug fixed

---

## [1.2.0] — 2026-06-15

### Added
- **Windows native port** — C# / WPF / .NET 8 monorepo alongside macOS
- **Signature vault** — multiple named signatures with carousel switching
- **Image editor** — rotate, contrast, thicken stroke, auto-trim, zoom, and white-canvas toggle
- **Native auto-updater** — lightweight GitHub Releases checker (replaces Sparkle)
- **CI/CD pipeline** — automated multi-platform builds and `v*` tag releases
- **Pen tools** — thickness adjustment and smart vectorization

### Changed
- **Project rename** — PersonalSignature → Ponten
- **Monorepo layout** — `macos/` and `windows/` top-level directories

### Fixed
- **Image processing** — async background tasks, debounced sliders, morphology clipping
- **Security** — symlink vulnerability patched in updater

---

## [1.1.0] — 2026-06-14

### Added
- **Built-in Drawing Canvas** — draw your signature natively using your trackpad, mouse, or Apple Pencil
- **Multiple signature profiles** — save and quickly switch between different signatures
- **Auto-Paste** — uses macOS Accessibility APIs to paste your signature directly into the active document
- **Global Shortcut presets (macOS)** — choose among ⌥⌘S, ⌃⌘S, or ⇧⌘S in popover settings
- **Drag & Drop Out** — drag the signature from the popover directly into target apps
- **Native Auto-Updater** — lightweight, native SwiftUI GitHub release checker

### Fixed
- **Background removal** — correctly drops white backgrounds while preserving original ink color
- **Memory leaks** — fixed memory leaks in the popover and signature processing
- **Drag and Drop** — fixed issues where drag & drop was not working reliably
- **Windows Memory Leaks** — fixed a memory leak in the Windows app where global shortcuts registered multiple event handlers to the UI thread dispatcher
- **Windows UI Issues** — fixed a UI flashing issue on startup in the Windows app
- **Windows Performance** — dramatically improved image processing performance for background removal in the Windows app by replacing GetPixel/SetPixel with LockBits

### Technical
- **Modular UI Refactoring** — split `MenuBarView` into `HeaderView`, `SignatureActiveView`, `FooterView`, `EmptyStateView`, `DrawingView`, and `AboutView` for better maintainability

---

## [1.0.0] — 2024-06-14

### Added
- Menu bar icon (`signature` SF Symbol, template — adapts to light/dark menu bar)
- **Add Signature** — pick PNG / JPEG / TIFF from Finder via file importer
- **Sign** — one-click copy of signature image to `NSPasteboard` (paste anywhere: Word, Google Docs, PDF editors, email, etc.)
- **Change Signature** — replace active signature at any time
- **Remove Signature** — delete saved signature with confirmation dialog
- **Drag & Drop** — drag a PNG/image file directly onto the popover (active & empty state)
- **Live preview** thumbnail in popover
- **Empty state** with dashed drop-zone and friendly messaging
- **Toast feedback** — animated "Signature copied to clipboard ✓" notification
- **Launch at Login** toggle via `SMAppService` (macOS 13+)
- **Global hotkey** ⌥⌘S — copy signature without opening popover
- **About panel** — version, GitHub link, shortcut hint
- **Persistent storage** in `~/Library/Application Support/Ponten/signature.png`
- **App Sandbox** with `user-selected.read-only` entitlement
- Unit tests for `SignatureManager` (7 test cases)
- GitHub Actions CI workflow (build + test + archive on main)
- `README.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `LICENSE` (MIT)

### Technical
- Swift 5.9 + SwiftUI + AppKit hybrid
- `LSUIElement = YES` — no Dock icon, no ⌘Tab entry
- `NSPasteboard.writeObjects([NSImage])` for universal image paste compatibility
- PNG re-encoding on save — normalizes any source format
- Thread-safe `@Published` state with main-thread dispatch
- `EventMonitor` for outside-click dismissal
- macOS 13.0 Ventura minimum deployment target

---

[Unreleased]: https://github.com/mustafabercerita/ponten/compare/v1.2.12...HEAD
[1.2.12]: https://github.com/mustafabercerita/ponten/compare/v1.2.0...v1.2.12
[1.2.0]: https://github.com/mustafabercerita/ponten/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/mustafabercerita/ponten/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/mustafabercerita/ponten/releases/tag/v1.0.0