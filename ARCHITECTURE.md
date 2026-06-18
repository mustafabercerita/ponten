# Architecture — Ponten (v1.2.14)

## Overview

Ponten is a **cross-platform menu-bar / system-tray application** (macOS + Windows) that stores one or more signature images and copies the active signature to the clipboard — optionally auto-pasting into the foreground app.

| Platform | Shell | Visibility |
|---|---|---|
| **macOS** | `NSStatusItem` + `NSPopover` + SwiftUI | No Dock icon (`LSUIElement`), no main window, no ⌘Tab entry (`NSApp.setActivationPolicy(.accessory)`) |
| **Windows** | `H.NotifyIcon` `TaskbarIcon` + borderless `MenuBarView` popup | Tray-only; `ShutdownMode.OnExplicitShutdown`, single-instance mutex |

There is no traditional main window on either platform. All interaction happens through a compact popup anchored to the tray icon.

---

## Repository Layout

```
Ponten/
├── macos/
│   ├── Ponten/
│   │   ├── App/           AppDelegate, PontenApp
│   │   ├── Models/        SignatureManager, SignatureStore, ImageProcessor
│   │   ├── Views/         MenuBarView, HeaderView, SignatureActiveView, …
│   │   └── Utilities/     GlobalShortcutManager, EventMonitor
│   ├── PontenTests/       XCTest unit tests (DI via init(store:))
│   ├── PontenUITests/     XCUITest E2E (MenuBarUITests.swift; CI / scheme)
│   └── PontenE2ETests/    Legacy AXUIElement E2E (skipped in scheme; local dev)
└── windows/
    ├── PontenWPF/             App, MenuBarView, SignatureStorage, ImageProcessor, …
    ├── PontenWPF.Tests/       xUnit (custom storage directory)
    └── PontenWPF.E2E.Tests/   FlaUI UI automation (isolated data-dir runs via E2ETestFixture)
```

---

## High-Level Layer Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  macOS Menu Bar                          Windows System Tray                   │
│  ┌───────────┐                           ┌───────────┐                        │
│  │  🖊 icon  │ ◄── NSStatusItem          │  🖊 icon  │ ◄── TaskbarIcon        │
│  └─────┬─────┘                           └─────┬─────┘                        │
│        │ click                                 │ left-click                   │
│        ▼                                       ▼                              │
│  ┌─────────────────────┐               ┌─────────────────────┐              │
│  │ NSPopover (300 pt)  │               │ MenuBarView Window  │              │
│  │ NSHostingController │               │ (bottom-right popup)│              │
│  │ └─ MenuBarView      │               │ └─ XAML UI          │              │
│  └─────────────────────┘               └─────────────────────┘              │
│        │ outside click                         │ Deactivated → Hide          │
│        ▼                                       ▼                              │
│  EventMonitor.closePopover()           (auto-hide on focus loss)            │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌──────────────────────────────────────────┐
                    │  Business Logic + Image Pipeline          │
                    │                                           │
                    │  macOS:  SignatureManager                 │
                    │          └─ SignatureStore (disk I/O)     │
                    │          └─ ImageProcessor (static ops)     │
                    │                                           │
                    │  Windows: SignatureStorage (disk + index) │
                    │           ImageProcessor (instance ops)   │
                    └──────────────────────────────────────────┘
                                      │
                                      ▼
                    ┌──────────────────────────────────────────┐
                    │  index.json  +  {UUID}.png files        │
                    └──────────────────────────────────────────┘
```

---

## macOS Architecture

### Entry & Shell

**`PontenApp`** (`@main`) — bridges SwiftUI to AppKit via `@NSApplicationDelegateAdaptor(AppDelegate.self)`. Declares `Settings { EmptyView() }` to suppress the default main window.

**`AppDelegate`** owns the full menu-bar lifecycle:

- `NSStatusItem` with template menu-bar icon (`MenuBarIconTemplate`)
- `NSPopover` hosting `MenuBarView` via `NSHostingController` (300 × 260–360 pt, height varies by state)
- `EventMonitor` — global mouse-down listener; closes popover on outside click (skipped while file dialog is open)
- `GlobalShortcutManager` — Carbon `RegisterEventHotKey`; action wired to `copySignatureToClipboard()`
- **Updater** — `URLSession` calls GitHub Releases API on launch, every 12 hours, and on manual "Check for Updates"; downloads `.dmg`, writes install script, quits and relaunches

Right-click on the status item shows a minimal context menu (Quit).

### `SignatureManager` — Orchestration Layer

`ObservableObject` singleton (`SignatureManager.shared`) used in production. Tests inject a custom `SignatureStore` via `init(store:)`.

| Responsibility | Implementation |
|---|---|
| **@Published state** | `signatures`, `activeSignatureID`, `toastMessage`, `pendingImageToEdit`, settings toggles |
| **Persistence** | Delegates to `SignatureStore` — writes `index.json` + PNG files |
| **Clipboard** | `NSPasteboard.general.writeObjects([NSImage])` |
| **Auto-paste** | `CGEvent` posts ⌘V via `pasteToActiveApp()` when `autoPaste` is enabled |
| **Settings** | `index.json` → `settings` (`autoPaste`, `launchAtLogin`, `removeBackground`, `globalShortcut`, `showWhiteCanvas`); UserDefaults mirrored for launch-time reads |
| **Launch at login** | `SMAppService.mainApp` (macOS 13+) |
| **File import** | `NSOpenPanel`, drag-and-drop, drawing sheet → sets `pendingImageToEdit` |
| **Multi-signature** | Add, select active, rename, delete; each stored as `{UUID}.png` |

Computed helpers: `signatureImage`, `signaturePath` resolve the active entry from `signatures` + `activeSignatureID`.

### `SignatureStore` — Persistence Layer

Owns the on-disk layout under `~/Library/Application Support/Ponten/`:

- **`index.json`** — manifest of signature items + active ID
- **`{UUID}.png`** — one PNG per signature (new saves use UUID filename)
- **Legacy migration** — if `index.json` is missing but `signature.png` exists, creates a single-item index pointing at the legacy file (filename kept as `signature.png` until next save)
- **Corrupt-index recovery** — rebuilds manifest from on-disk PNGs; renames legacy `signature.png` to `{UUID}.png` during rebuild
- **Lazy image load** — `loadImage(filename:)` called on demand via `SignatureManager.image(for:)` when signature cards appear

API: `load()`, `loadActiveID()`, `saveIndex(items:activeID:)`, `writePNG(data:filename:)`, `deleteFile(filename:)`, `filePath(for:)`.

### `ImageProcessor` — Image Pipeline

Static image operations plus `NSImage` extensions:

| Operation | Method |
|---|---|
| Thicken strokes | `thickenLines(image:radius:)` — Core Image morphology minimum |
| Color adjust | `adjustColor(image:contrast:brightness:)` |
| Rotate | `rotate(image:degrees:)` |
| Trim whitespace | `autoTrimWhitespace(image:padding:)` |
| Remove white BG | `NSImage.removingWhiteBackground()` — CI invert + blendWithMask |
| Edge validation | `NSImage.hasPredominantlyWhiteOrTransparentEdges()` |
| Vectorize | `NSImage.replacingWithVectorizedStroke()` — Vision `VNDetectContoursRequest` |

`SignatureManager.saveSignature(image:…)` orchestrates vectorize → PNG encode → store write → index update.

### SwiftUI Views

**`MenuBarView`** — root popover content. Switches between `SignatureActiveView` and `EmptyStateView` based on `manager.signatures.isEmpty`. Presents sheets for `DrawingView` and `ImageEditorView` (triggered by `pendingImageToEdit`). Overlays `ToastView`.

| View | Role |
|---|---|
| `HeaderView` | Logo, app name, version badge |
| `SignatureActiveView` | Horizontal signature grid, Sign button, add/draw/rename/delete, drop target |
| `EmptyStateView` | Onboarding drop zone, Add Signature / Draw buttons |
| `FooterView` | Launch at login, auto-paste, shortcut picker, Check for Updates, About, Quit |
| `DrawingView` | Canvas drawing with pen styles; saves via `SignatureManager` |
| `ImageEditorView` | Live preview editor (rotate, thicken, contrast, trim, remove BG) before save |
| `AboutView` | Version info popover |
| `Components.swift` | `PrimaryButtonStyle`, `ToastView` |

### `GlobalShortcutManager` (Carbon)

Singleton registering a global hotkey via `RegisterEventHotKey`. Three presets mapped to `ShortcutChoice`:

- `⌥⌘S` (default)
- `⌃⌘S`
- `⇧⌘S`

Persisted in `index.json` (`settings.globalShortcut`) with UserDefaults mirror; `SignatureManager.globalShortcut` setter calls `updateShortcut(_:)`. If hotkey fires with no signature loaded, `AppDelegate` opens the popover instead.

### `EventMonitor`

Thin wrapper around `NSEvent.addGlobalMonitorForEvents`. Started when popover opens, stopped when it closes.

---

## Windows Architecture

### Entry & Shell

**`App.xaml.cs`** — WPF application entry:

- Single-instance `Mutex` (`PontenWPF.SingleInstance`; in E2E mode, per-run mutex hashed from data dir — see [Windows E2E / Test Harness](#windows-e2e--test-harness))
- `H.NotifyIcon` `TaskbarIcon` with extracted `.exe` icon (fallback: `Assets/Ponten.ico`)
- Context menu: Open, Add Signature, Draw Signature, Quit
- Left-click toggles `MenuBarView` visibility
- File logging to `%LocalAppData%\Ponten\logs\app.log`

**`MenuBarView`** — borderless popup window positioned at bottom-right of work area. Hides on `Deactivated` (click outside). Owns `SignatureStorage`, `ImageProcessor`, and `GlobalShortcutManager`.

Supporting windows:

| Window | Role |
|---|---|
| `DrawSignatureWindow` | Ink canvas; saves PNG via `SignatureStorage.AddSignature` |
| `ImageEditorWindow` | Thickness, contrast, rotation, trim, background removal preview |

### `SignatureStorage` — Persistence + Settings

Single class handling disk I/O and embedded settings.

Storage root: `%LocalAppData%\Ponten\`

- Loads / saves `index.json` (items, activeID, settings including `GlobalShortcut`)
- Cleans index entries whose PNG files are missing on load
- **Legacy migration** — renames `signature.png` to `{UUID}.png` on load and during corrupt-index recovery
- **SaveIndex errors** — raises `IndexSaveFailed` event surfaced to UI via `ShowStatus`
- `ApplyLaunchAtLogin` — writes/removes `HKCU\...\Run\PontenSignatures` registry value (legacy key name; the app displays **Ponten** in the UI)
- Testable via `SignatureStorage(string? customStorageDirectory)`

### `ImageProcessor.cs` — Image Operations

Instance methods (previously lived in a monolithic manager; refactored to match macOS separation):

| Operation | Method |
|---|---|
| White-edge validation | `ValidateWhiteBackground(Bitmap)` |
| Strip white BG | `StripWhiteBackground(Bitmap)` |
| Thicken / dilate | `Dilation(Bitmap, thickness)` |
| Color adjust | `AdjustColor(Bitmap, contrast, brightness)` |
| Rotate | `Rotate(Bitmap, angle)` |
| Trim whitespace | `AutoTrimWhitespace(Bitmap, padding)` |
| Auto-paste | `AutoPaste()` — `keybd_event` Ctrl+V (releases Alt/Shift/Win first) |

No vectorization on Windows.

### `GlobalShortcutManager`

Win32 `RegisterHotKey` via P/Invoke. Registration in `MenuBarView_SourceInitialized` reads `Settings.GlobalShortcut`:

- **Ctrl + Alt + S** (default) — `MOD_CONTROL | MOD_ALT`, `VK_S`
- **Ctrl + Shift + S** — `MOD_CONTROL | MOD_SHIFT`, `VK_S`
- **Alt + Shift + S** — `MOD_ALT | MOD_SHIFT`, `VK_S`

Three presets via `ShortcutChoice` enum; picker in footer (`GlobalShortcutCombo`) persists choice to `index.json`. Dynamic labels in Sign button, About dialog, and status toasts.

Hotkey handler: `HandleHotKeyAsync()` copies the active signature and respects `Settings.AutoPaste` (same as the Sign button). If no signature is loaded, opens the popup instead of copying.

**Auto-paste focus fix** — `CaptureAutoPasteTargetWindow()` records foreground HWND via `GetForegroundWindow()` before the popup hides, so paste targets the correct window.

### `Updater.cs`

`HttpClient`-based GitHub Releases check and download helper (`CheckForUpdateAsync`, `DownloadUpdateAndExecute`). Wired to the UI via `CheckUpdates_Click` — prompts to download and install when a newer release is available.

---

## macOS E2E / Test Harness

macOS UI automation tests live in `PontenUITests/` and launch the real `Ponten.app` via XCUITest (`XCUIApplication`). Five tests in `MenuBarUITests.swift` mirror the Windows FlaUI suite (empty state, seeded signature, copy marker, auto-paste persistence, restart).

### `E2EMode.swift` — activation & data isolation

`E2EMode` reads launch arguments and environment at startup:

| Switch | Source |
|---|---|
| **E2E enabled** | CLI `--e2e` **or** env `PONTEN_E2E=1` |
| **Data directory** | Env `PONTEN_DATA_DIR` **or** CLI `--data-dir=<path>` |

When enabled, `SignatureManager` uses `E2EMode.dataDirectory` so each test run uses an isolated temp folder instead of `~/Library/Application Support/Ponten/`.

### App startup branches in E2E

In `AppDelegate.applicationDidFinishLaunching`:

- **E2E window** — `setupE2EWindow()` shows the menu panel immediately (no status-item click required)
- **Global shortcut** — skipped when `E2EMode.isEnabled`
- **Auto-paste** — skipped in E2E (same as Windows)

### Clipboard substitute — `e2e-last-copy.txt`

E2E mode does not touch the system clipboard. On copy, `SignatureManager` writes `{dataDir}/e2e-last-copy.txt` with a UTC timestamp. `MenuBarUITests` polls for this file to assert copy success.

### `PontenUITests` (XCUITest)

`MenuBarUITests` sets `PONTEN_E2E=1` and passes `--data-dir=<temp>` via launch arguments. Tests seed signatures into the isolated data directory, launch `Ponten.app`, and query accessibility-exposed UI elements (`windows["Ponten Menu"]`, buttons, toggles).

### Legacy `PontenE2ETests`

`PontenE2ETests/` retains an older Accessibility (`AXUIElement`) + optional in-process hosting path. The `Ponten` scheme marks this target **skipped** (`skipped = "YES"` in `Ponten.xcscheme`); use it only for local AX debugging, not CI.

---

## Windows E2E / Test Harness

Windows UI automation tests live in `PontenWPF.E2E.Tests/` and drive the real `PontenWPF.exe` via [FlaUI](https://github.com/FlaUI/FlaUI) (UIA3).

### `E2EMode.cs` — activation & data isolation

`E2EMode.Initialize(args)` runs at app startup and sets two flags:

| Switch | Source |
|---|---|
| **E2E enabled** | CLI `--e2e` **or** env `PONTEN_E2E=1` |
| **Data directory** | Env `PONTEN_DATA_DIR` **or** CLI `--data-dir=<path>` (also accepts `--data-dir <path>`) |

When enabled, `SignatureStorage` is constructed with `E2EMode.DataDirectory` so each test run uses an isolated temp folder instead of `%LocalAppData%\Ponten\`.

### App startup branches in E2E

In `App.xaml.cs` `OnStartup`:

- **Mutex** — `PontenWPF.E2E.{dataDirHash}` (hash of data dir) instead of `PontenWPF.SingleInstance`, allowing parallel E2E runs with different data dirs
- **Tray skipped** — `TaskbarIcon` / `H.NotifyIcon` setup is bypassed
- **Visible window** — `MenuBarView` is created, shown, and activated directly (no tray click required)
- **Duplicate instance** — exits silently (no MessageBox) when another instance holds the same E2E mutex

`MenuBarView` also adapts in E2E: auto-shows on load, does not hide on `Deactivated`, and keeps status text visible.

### Clipboard substitute — `e2e-last-copy.txt`

E2E mode does not touch the system clipboard (avoids flaky automation and permission issues). On copy, `CopyActiveSignatureToClipboard` writes `{dataDir}/e2e-last-copy.txt` with a UTC timestamp. `E2ETestFixture.WaitForCopyMarker()` polls for this file to assert copy success.

Auto-paste is also skipped in E2E (`autoPaste && !E2EMode.IsEnabled`).

### `E2ETestFixture` (FlaUI)

`PontenWPF.E2E.Tests/E2ETestFixture.cs` is the shared fixture:

- Resolves `PontenWPF.exe` from build output (`CONFIGURATION` env, default `Release`)
- Launches with `--e2e --data-dir="<temp>"` plus `PONTEN_E2E=1` and `PONTEN_DATA_DIR`
- Kills stale `PontenWPF` processes between runs
- Waits for the `Ponten Menu` window via UIA3
- Provides helpers: `RequireElement`, `WaitForCopyMarker`, `SeedSignature`, `AssertAutoPastePersisted`
- Cleans up temp data dir on dispose (unless a pre-seeded dir was passed in)

`MenuBarE2ETests` uses `[Collection("E2E")]` with `DisableParallelization = true` to avoid mutex/UI conflicts.

---

## Storage Schema (Both Platforms)

### Directory Layout

```
macOS:   ~/Library/Application Support/Ponten/
Windows: %LocalAppData%\Ponten\
         └── logs\app.log          (Windows only)

├── index.json
├── a1b2c3d4-….png               ← new signatures
├── e5f6g7h8-….png
└── signature.png                 ← legacy (macOS migration only; filename preserved)
```

### `index.json` Structure

**macOS** (`IndexWrapper` + embedded settings, camelCase on write):

```json
{
  "items": [
    { "id": "UUID", "filename": "UUID.png", "name": "Work" }
  ],
  "activeID": "UUID",
  "settings": {
    "autoPaste": true,
    "launchAtLogin": false,
    "removeBackground": true,
    "globalShortcut": 0,
    "showWhiteCanvas": true
  }
}
```

**Windows** (`IndexWrapper` + embedded settings, PascalCase on write; case-insensitive read):

```json
{
  "items": [
    { "id": "UUID", "filename": "UUID.png", "name": null }
  ],
  "activeID": "UUID",
  "settings": {
    "LaunchAtLogin": false,
    "AutoPaste": true,
    "RemoveBackground": true,
    "GlobalShortcut": 0
  }
}
```

### File Naming

- **New signatures**: `{UUID}.png` where UUID matches the `SignatureItem.id`
- **Legacy migration (both platforms)**: pre-v1.2 installs stored a single `signature.png`. On first load without `index.json`, both platforms create an index entry; on subsequent load/save or corrupt-index rebuild, the file is renamed to `{UUID}.png`

### Settings Storage Split

| Setting | macOS | Windows |
|---|---|---|
| Launch at login | `index.json` → `settings.launchAtLogin` + `SMAppService` | `index.json` → `settings.LaunchAtLogin` + Registry Run key (`PontenSignatures`) |
| Auto-paste | `index.json` → `settings.autoPaste` | `index.json` → `settings.AutoPaste` |
| Remove background default | `index.json` → `settings.removeBackground` | `index.json` → `settings.RemoveBackground` |
| Global shortcut | `index.json` → `settings.globalShortcut` | `index.json` → `settings.GlobalShortcut` |
| Show white canvas | `index.json` → `settings.showWhiteCanvas` | N/A |

---

## Data Flows

### 1. Add Signature (File Picker → Editor → Save)

```
User clicks "Add Signature" (or tray context menu)
        │
        ▼
macOS: NSOpenPanel / drag-drop          Windows: OpenFileDialog
        │                                        │
        ▼                                        ▼
Validate white/transparent edges        ValidateWhiteBackground()
        │                                        │
        ▼                                        ▼
Set pendingImageToEdit                  Open ImageEditorWindow
        │                                        │
        ▼                                        ▼
ImageEditorView (live preview)          ImageEditorWindow (debounced preview)
  rotate, thicken, trim, remove BG       same controls (no vectorize)
        │                                        │
        ▼                                        ▼
SignatureManager.saveSignature()        Write {UUID}.png + AddSignature()
  vectorize (macOS) → PNG encode          to SignatureStorage
  SignatureStore.writePNG + saveIndex
        │
        ▼
@Published signatures updates → UI shows SignatureActiveView / list
```

### 2. Copy + Auto-Paste Flow

```
User clicks "Sign" (or selects signature on Windows)
        │
        ▼
Copy image to system clipboard
        │
        ├─ macOS: NSPasteboard.writeObjects([NSImage])
        └─ Windows: Clipboard.SetImage(BitmapImage)
        │
        ▼
If auto-paste enabled:
        │
        ├─ macOS: CGEvent ⌘V (requires Accessibility permission prompt)
        └─ Windows: keybd_event Ctrl+V
        │
        ▼
Toast / hide popup → focus returns to previous app
```

### 3. Global Hotkey Flow

```
Hotkey pressed
        │
        ├─ macOS: Carbon EventHotKey → GlobalShortcutManager.action
        │          → SignatureManager.copySignatureToClipboard()
        │          → if no signature: open popover
        │
        └─ Windows: WM_HOTKEY → GlobalShortcutManager.HotKeyPressed
                   → HandleHotKeyAsync() → copy + AutoPaste if Settings.AutoPaste
                   → if no signature: show popup
```

### 4. Draw Signature Flow

```
"Draw Signature" → DrawingView (macOS sheet) / DrawSignatureWindow (Windows)
        │
        ▼
User draws on white canvas
        │
        ▼
Save → PNG encode → new UUID entry in index + disk
```

---

## Platform Parity

| Feature | macOS | Windows |
|---|---|---|
| Tray-only UI | ✅ `NSPopover` | ✅ Popup window |
| Multiple signatures | ✅ | ✅ |
| Rename signatures | ✅ context menu | ✅ `RenameSignature_Click` |
| Draw signature | ✅ `DrawingView` | ✅ `DrawSignatureWindow` |
| Image editor | ✅ `ImageEditorView` | ✅ `ImageEditorWindow` |
| Background removal | ✅ CI filters | ✅ pixel strip |
| Vectorize on save | ✅ Vision contours | ❌ |
| Drag & drop import | ✅ | ✅ `Grid_DragOver` / `Grid_Drop` |
| Drag & drop out | ✅ `.onDrag` from signature cards | ✅ file-drop drag from list items |
| Global hotkey | ✅ 3 presets (⌥⌘S default) | ✅ 3 presets (Ctrl+Alt+S default) |
| Shortcut customization | ✅ Picker in footer | ✅ `GlobalShortcutCombo` in footer |
| Auto-paste toggle | ✅ respects setting | ✅ respects `Settings.AutoPaste` via `HandleHotKeyAsync` |
| Launch at login | ✅ `SMAppService` | ✅ Registry Run key (`PontenSignatures`); cleaned on uninstall |
| Auto-updater | ✅ GitHub API + DMG install | ✅ `CheckUpdates_Click` + `Updater.cs` |
| Legacy `signature.png` migration | ✅ UUID rename on rebuild | ✅ UUID rename on load/rebuild |
| Settings location | `index.json` (UserDefaults mirror) | `index.json` |
| Lazy thumbnail load | ✅ on card appear | N/A (loads on list bind) |
| Storage error surfacing | ✅ toast via `StorageError` | ✅ `ShowStatus` via `IndexSaveFailed` + `StorageError` |
| DI for tests | ✅ `init(store:)` | ✅ custom storage directory ctor |
| Logging | `print` / toasts | `%LocalAppData%\Ponten\logs\app.log` |

---

## Dependency Injection & Testing

**macOS** — `SignatureManager` accepts `SignatureStore(storageDirectory:)` in its initializer. Production uses `SignatureManager.shared` (default store path). `PontenTests` create a temp directory and inject `SignatureManager(store: testStore)`.

| Project | Scope | Isolation |
|---|---|---|
| `PontenTests` | XCTest unit tests | `SignatureManager(store:)` with temp `SignatureStore` |
| `PontenUITests` | XCUITest end-to-end UI tests | Launches `Ponten.app` with `PONTEN_E2E=1` and `--data-dir=<temp>` |
| `PontenE2ETests` | Legacy AX E2E (local dev) | Same E2E flags; skipped in `Ponten` scheme |

**Windows** — two test layers:

| Project | Scope | Isolation |
|---|---|---|
| `PontenWPF.Tests` | xUnit unit tests | `SignatureStorage(customStorageDirectory:)` — temp dir, no `%LocalAppData%` |
| `PontenWPF.E2E.Tests` | FlaUI end-to-end UI tests | `E2ETestFixture` launches `PontenWPF.exe` with `--e2e --data-dir=<temp>` and `PONTEN_E2E=1` |

E2E tests exercise real window interactions (copy marker, settings persistence, restart) against an isolated data directory; unit tests cover storage and image logic without launching the app.

---

## Design Decisions

| Decision | Rationale |
|---|---|
| Split `SignatureManager` / `SignatureStore` / `ImageProcessor` (macOS) | Separates orchestration, persistence, and image math; enables testable DI |
| `index.json` manifest + UUID PNG files | Supports multiple signatures without a database |
| SwiftUI inside `NSPopover` | Reactive UI with minimal AppKit boilerplate |
| Carbon hotkeys (macOS) / Win32 `RegisterHotKey` (Windows) | System-wide shortcuts that work while other apps are focused |
| `LSUIElement` + `.accessory` activation policy | True menu-bar agent — no Dock or switcher clutter |
| Windows single-instance mutex | Prevents duplicate tray icons |
| Re-encode PNG on save | Normalizes any input format to consistent transparent PNG |

---

## Version Support

| Platform | Minimum | Stack |
|---|---|---|
| macOS | 13.0 Ventura | Swift 5.9, SwiftUI, AppKit, Vision, Core Image |
| Windows | 10 | .NET 8, WPF, `System.Drawing` |

Current release: **v1.2.14**

---

## Security & Privacy

### Network

- **macOS updater** uses `URLSession` to call `api.github.com/repos/mustafabercerita/ponten/releases/latest`, download release assets, and install via a shell script. This is real outbound network usage — not offline-only.
- **Windows updater** uses `Updater.cs` (`HttpClient`) via `CheckUpdates_Click` to query GitHub Releases and download/install updates.
- No analytics, telemetry, or third-party SDKs on either platform.

### macOS Entitlements (`Ponten.entitlements`)

What is actually declared:

```xml
com.apple.security.app-sandbox                    → true
com.apple.security.files.user-selected.read-only  → true
com.apple.security.files.downloads.read-write     → false
```

Not declared: `com.apple.security.network.client` (required for sandboxed outbound HTTP). Signature PNGs are written to the app's sandboxed Application Support container (writable within the container without a separate entitlement). For direct distribution, the entitlements file notes that sandboxing can be disabled by removing `CODE_SIGN_ENTITLEMENTS`.

### Permissions

| Permission | Why |
|---|---|
| **Accessibility** (macOS) | Auto-paste posts synthetic ⌘V events via `CGEvent` |
| **User-selected files** (macOS sandbox) | `NSOpenPanel` / security-scoped file access for imports |

### Data Handling

- All signature data stays local on disk.
- No cloud sync, accounts, or encryption layer — plain PNG + JSON files the user can inspect directly.