# Ponten — AI Agent Guidelines

Welcome to **Ponten**, a cross-platform menu-bar signature app (macOS + Windows). Read this document before modifying code or pushing changes.

## 1. Project Architecture

Ponten is **100% native** on both platforms — no Electron, no web views.

| Platform | Stack | Entry point |
|----------|-------|-------------|
| **macOS** | AppKit + SwiftUI | `MenuBarView` in an `NSPopover` (`AppDelegate`) |
| **Windows** | WPF (.NET 8) | `MenuBarView.xaml` (assigned to `Application.MainWindow`) |

**Menu-bar only** — no Dock icon (macOS `LSUIElement`), no traditional main window. On Windows, `MainWindow.xaml` exists as a scaffold but is **not** the primary UI; `MenuBarView.xaml` is.

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
  -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO

# or via SPM:
swift test
```

### Windows

```bash
cd windows
dotnet test Ponten.sln -c Release
```

### CI (`.github/workflows/ci.yml`)

Runs on every push/PR to `main`/`develop` and on `v*` tags:

- **macOS**: Debug build → unit tests → Release archive (on `main`)
- **Windows**: `dotnet test` → publish single-file exe → Inno Setup (on tags)
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
| `macos/install.sh` | `VERSION=` |
| `macos/build-dmg.sh` | `VERSION=` |

### `index.json` schema differences

Both platforms store signatures in a platform-specific app-data folder with an `index.json` manifest, but schemas differ:

| Field | macOS (`SignatureStore`) | Windows (`SignatureStorage`) |
|-------|--------------------------|------------------------------|
| Items key | `items` (camelCase) | `Items` (PascalCase; deserializer is case-insensitive) |
| Active ID | `activeID` | `ActiveID` |
| Settings | ❌ not in index | ✅ `Settings` (`LaunchAtLogin`, `AutoPaste`) |
| Storage path | `~/Library/Application Support/Ponten/` | `%LOCALAPPDATA%\Ponten\` |

Do not assume cross-platform index file compatibility.

---

## 7. Attitude

- Be thorough and meticulous.
- Double-check before concluding.
- If something breaks, fix it immediately.

See also: `DEVELOPMENT.md` (build commands), `CONTRIBUTING.md` (PR flow), `ARCHITECTURE.md` (deeper macOS diagram).