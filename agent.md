# Ponten — AI Agent Guidelines

Welcome to **Ponten**, a cross-platform menu-bar signature app (macOS + Windows). Read this document before modifying code or pushing changes.

## 1. Project Architecture

Ponten is **100% native** on both platforms — no Electron, no web views.

| Platform | Stack | Entry point |
|----------|-------|-------------|
| **macOS** | AppKit + SwiftUI | `MenuBarView` in an `NSPopover` (`AppDelegate`) |
| **Windows** | WPF (.NET 8) | `MenuBarView.xaml` (assigned to `Application.MainWindow`) |

**Menu-bar only** — no Dock icon (macOS `LSUIElement`), no traditional main window. On Windows, `App.xaml.cs` assigns `Application.MainWindow` to a `MenuBarView` instance — there is no `MainWindow.xaml`.

**Data flow**: `NotificationCenter` (macOS) and direct method calls (Windows) for cross-component events (updates, popover close, etc.).

---

## 2. Strict Workflow Rules (CRITICAL)

1. **Plan first** — understand the full scope before editing.
2. **Implement & test** — run platform tests (see §5) and verify the app builds.
3. **Update documentation** — if you completed a roadmap item, move it to ✅ **Completed** in `README.md`.
4. **Final double-check** — docs, version bumps, new Swift files synced to Xcode.
5. **Commit & push** — only after docs are updated and tests/build pass.

---

## 3. macOS

### Module split

| Type | File | Role |
|------|------|------|
| Persistence | `SignatureStore.swift` | Disk I/O: `index.json`, PNG files in Application Support |
| Business logic | `SignatureManager.swift` | UI state, clipboard, auto-paste, orchestration |
| Image ops | `ImageProcessor.swift` | Background removal, validation, vectorization |

`SignatureManager` accepts `init(store:)` for dependency injection — tests inject a temp-directory `SignatureStore`.

### Dependencies

No third-party Swift packages in the Xcode target. Sparkle was removed; the updater lives in `AppDelegate` using `URLSession` + GitHub Releases API (not Sparkle).

### Xcode project maintenance

When adding new `.swift` files under `macos/Ponten/` or `macos/PontenTests/`:

```bash
gem install xcodeproj   # once
ruby add_files.rb       # from repo root
```

`add_files.rb` syncs `Views/`, `Models/`, and `PontenTests/` into `Ponten.xcodeproj`.

### SPM layout

`macos/Package.swift` defines `Ponten` (executable) and `PontenTests` targets for command-line builds/tests. Paths are relative to `macos/`.

### Notable features

- **Native auto-updater** (`AppDelegate.checkForUpdates`): `URLSession` → GitHub Releases API → download `.dmg` → replace bundle → restart.
- **Auto-paste**: `CGEvent` posts `Cmd+V` (virtual key `0x09`) — **not** `AXUIElement`.
- **Background removal**: CoreImage `colorInvert` + `blendWithMask` — **not** `CIColorCube`.
- **Global shortcuts**: Carbon `RegisterEventHotKey` (`GlobalShortcutManager`).
- **Drawing**: SwiftUI `Canvas` + `ImageRenderer`.

---

## 4. Windows

### Module split (names differ from macOS — do not confuse)

| Type | File | Role |
|------|------|------|
| Persistence + settings | `SignatureStorage.cs` | `index.json`, PNG files, `UserSettings` |
| Image ops | `ImageProcessor.cs` | Background removal, image processing |

There is **no** `SignatureManager` on Windows — logic lives in `MenuBarView.xaml.cs` and helpers.

### UI

- **`MenuBarView.xaml`** — primary popover UI (system-tray flyout).
- **`App.xaml.cs`** — owns `H.NotifyIcon.TaskbarIcon`, single-instance mutex, shows/hides `MenuBarView`.

### Dependencies

`H.NotifyIcon.Wpf` is the **only** third-party dependency (system-tray icon). Also uses `System.Drawing.Common` (Microsoft package).

### Installer

Release builds use **Inno Setup**: `windows/installer.iss`. CI compiles it on version tags.

---

## 5. Testing & CI

### macOS

```bash
cd macos
xcodebuild test -project Ponten.xcodeproj -scheme Ponten \
  -destination "platform=macOS,arch=arm64" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO

# or via SPM:
swift test
```

**E2E tests** (`PontenUITests`): 5 XCUITest cases in `MenuBarUITests.swift` that launch `Ponten.app` and drive the menu UI via `XCUIApplication`. macOS-only; run via `-only-testing:PontenUITests` or the `Ponten` scheme (CI). Legacy `PontenE2ETests` (AX-based) are skipped in the scheme — local debugging only.

```bash
cd macos
xcodebuild test -project Ponten.xcodeproj -scheme Ponten \
  -destination "platform=macOS" -only-testing:PontenUITests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

### Windows

```bash
cd windows
dotnet test Ponten.sln -c Release   # unit (35) + E2E (5)
```

**Windows E2E tests** (`PontenWPF.E2E.Tests`): 5 FlaUI + xUnit tests that launch `PontenWPF.exe` and drive the tray popover UI. Windows-only; requires a prior build of `PontenWPF` (the test fixture locates `PontenWPF.exe` under `bin/`).

**E2E mode flags** (set by the test fixture; useful for manual debugging):

| Flag / env | Purpose |
|------------|---------|
| `--e2e` or `PONTEN_E2E=1` | Enable E2E mode (show window immediately, skip tray-only behaviors) |
| `PONTEN_DATA_DIR` or `--data-dir=<path>` | Isolated storage directory for test data |

### CI (`.github/workflows/ci.yml`)

Runs on every push/PR to `main`/`develop` and on `v*` tags:

- **macOS**: Debug build → unit + E2E tests → Release archive (on `main`)
- **Windows** (`windows-latest`): `dotnet test Ponten.sln -c Release` (unit + E2E) → publish single-file exe → Inno Setup (on tags)
- **Release job** (on tags): `build-dmg.sh` + upload DMG + Windows artifacts to GitHub Releases

---

## 6. Cross-Platform

### Version bump checklist

Bump **all** of these together, then `git tag vX.Y.Z`:

| File | Field |
|------|-------|
| `macos/Ponten/Resources/Info.plist` | `CFBundleShortVersionString` |
| `macos/Ponten.xcodeproj/project.pbxproj` | `MARKETING_VERSION` |
| `windows/PontenWPF/PontenWPF.csproj` | `<Version>`, `<AssemblyVersion>`, `<FileVersion>`, `<InformationalVersion>` |
| `windows/installer.iss` | `#define MyAppVersion` |
| `macos/install.sh` | `VERSION=` and `SOURCE_FILES` |
| `macos/build-dmg.sh` | `VERSION=` and `SOURCE_FILES` |

### `index.json` schema differences

Both platforms store signatures in a platform-specific app-data folder with an `index.json` manifest, but schemas differ:

| Field | macOS (`SignatureStore`) | Windows (`SignatureStorage`) |
|-------|--------------------------|------------------------------|
| Items key | `items` (camelCase) | `Items` (PascalCase on write; deserializer is case-insensitive) |
| Active ID | `activeID` | `ActiveID` |
| Settings | ✅ `settings` (`autoPaste`, `launchAtLogin`, `removeBackground`, `globalShortcut`, `showWhiteCanvas`) | ✅ `Settings` (`LaunchAtLogin`, `AutoPaste`, `RemoveBackground`, `GlobalShortcut`) |
| Storage path | `~/Library/Application Support/Ponten/` | `%LOCALAPPDATA%\Ponten\` |

Windows writes `index.json` with PascalCase property names (default `System.Text.Json` serialization).

Do not assume cross-platform index file compatibility.

---

## 7. Attitude

- Be thorough and meticulous.
- Double-check before concluding.
- If something breaks, fix it immediately.

See also: `DEVELOPMENT.md` (build commands), `CONTRIBUTING.md` (PR flow), `ARCHITECTURE.md` (deeper architecture for both platforms).