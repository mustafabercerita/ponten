# Architecture — Ponten (v1.2.12)

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
│   └── PontenTests/       XCTest (DI via init(store:))
└── windows/
    ├── PontenWPF/         App, MenuBarView, SignatureStorage, ImageProcessor, …
    └── PontenWPF.Tests/   xUnit (custom storage directory)
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
| **Settings (UserDefaults)** | `ShowWhiteCanvas`, `AutoPasteEnabled`, `GlobalShortcut` |
| **Launch at login** | `SMAppService.mainApp` (macOS 13+) |
| **File import** | `NSOpenPanel`, drag-and-drop, drawing sheet → sets `pendingImageToEdit` |
| **Multi-signature** | Add, select active, rename, delete; each stored as `{UUID}.png` |

Computed helpers: `signatureImage`, `signaturePath` resolve the active entry from `signatures` + `activeSignatureID`.

### `SignatureStore` — Persistence Layer

Owns the on-disk layout under `~/Library/Application Support/Ponten/`:

- **`index.json`** — manifest of signature items + active ID
- **`{UUID}.png`** — one PNG per signature (new saves use UUID filename)
- **Legacy migration** — if `index.json` is missing but `signature.png` exists, creates a single-item index pointing at the legacy file (filename kept as `signature.png`)

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

Persisted in UserDefaults; `SignatureManager.globalShortcut` setter calls `updateShortcut(_:)`. If hotkey fires with no signature loaded, `AppDelegate` opens the popover instead.

### `EventMonitor`

Thin wrapper around `NSEvent.addGlobalMonitorForEvents`. Started when popover opens, stopped when it closes.

---

## Windows Architecture

### Entry & Shell

**`App.xaml.cs`** — WPF application entry:

- Single-instance `Mutex` (`PontenWPF.SingleInstance`)
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

Single class handling disk I/O and embedded settings (unlike macOS, where settings split between `index.json` and UserDefaults).

Storage root: `%LocalAppData%\Ponten\`

- Loads / saves `index.json` (items, activeID, settings)
- Cleans index entries whose PNG files are missing on load
- `ApplyLaunchAtLogin` — writes/removes `HKCU\...\Run\PontenSignatures` registry value
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

Win32 `RegisterHotKey` via P/Invoke. Fixed registration in `MenuBarView_SourceInitialized`:

- **Ctrl + Alt + S** (`MOD_CONTROL | MOD_ALT`, `VK_S`)
- Hotkey handler: copy active signature to clipboard + `AutoPaste()` (always pastes on hotkey; does not check `Settings.AutoPaste`)

`SetShortcut_Click` shows a stub dialog: *"Shortcut customization is coming soon."*

### `Updater.cs`

`HttpClient`-based download helper (`DownloadUpdateAndExecute`). Exists as infrastructure but is **not wired** to the UI — `CheckUpdates_Click` currently shows a static "up to date" message.

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

**macOS** (`IndexWrapper`):

```json
{
  "items": [
    { "id": "UUID", "filename": "UUID.png", "name": "Work" }
  ],
  "activeID": "UUID"
}
```

**Windows** (`IndexWrapper` + embedded settings):

```json
{
  "items": [
    { "id": "UUID", "filename": "UUID.png", "name": null }
  ],
  "activeID": "UUID",
  "settings": {
    "launchAtLogin": false,
    "autoPaste": true
  }
}
```

### File Naming

- **New signatures**: `{UUID}.png` where UUID matches the `SignatureItem.id`
- **Legacy migration (macOS only)**: pre-v1.2 installs stored a single `signature.png`. On first load without `index.json`, `SignatureStore.migrateLegacySignature()` creates an index entry with the existing file (filename stays `signature.png`)
- **Windows**: no legacy migration path; expects `index.json` from the start

### Settings Storage Split

| Setting | macOS | Windows |
|---|---|---|
| Launch at login | `SMAppService` + `@Published launchAtLogin` | `index.json` → `settings.launchAtLogin` + Registry Run key |
| Auto-paste | UserDefaults `AutoPasteEnabled` | `index.json` → `settings.autoPaste` |
| Global shortcut | UserDefaults `GlobalShortcut` | Hard-coded Ctrl+Alt+S (stub UI) |
| Show white canvas | UserDefaults `ShowWhiteCanvas` | N/A |

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
                   → Clipboard.SetImage(active) + AutoPaste() (always)
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
| Rename signatures | ✅ context menu | ❌ |
| Draw signature | ✅ `DrawingView` | ✅ `DrawSignatureWindow` |
| Image editor | ✅ `ImageEditorView` | ✅ `ImageEditorWindow` |
| Background removal | ✅ CI filters | ✅ pixel strip |
| Vectorize on save | ✅ Vision contours | ❌ |
| Drag & drop import | ✅ | ❌ (file picker only) |
| Global hotkey | ✅ 3 presets (⌥⌘S default) | ✅ fixed Ctrl+Alt+S |
| Shortcut customization | ✅ Picker in footer | ⚠️ Stub ("coming soon") |
| Auto-paste toggle | ✅ respects setting | ✅ UI toggle; hotkey always pastes |
| Launch at login | ✅ `SMAppService` | ✅ Registry Run key |
| Auto-updater | ✅ GitHub API + DMG install | ⚠️ `Updater.cs` exists; UI not wired |
| Legacy `signature.png` migration | ✅ | ❌ |
| Settings location | UserDefaults + index.json | index.json only |
| DI for tests | ✅ `init(store:)` | ✅ custom storage directory ctor |
| Logging | `print` / toasts | `%LocalAppData%\Ponten\logs\app.log` |

---

## Dependency Injection & Testing

**macOS** — `SignatureManager` accepts `SignatureStore(storageDirectory:)` in its initializer. Production uses `SignatureManager.shared` (default store path). `PontenTests` create a temp directory and inject `SignatureManager(store: testStore)`.

**Windows** — `SignatureStorage(customStorageDirectory:)` constructor enables isolated xUnit tests without touching `%LocalAppData%`.

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

Current release: **v1.2.12**

---

## Security & Privacy

### Network

- **macOS updater** uses `URLSession` to call `api.github.com/repos/mustafabercerita/ponten/releases/latest`, download release assets, and install via a shell script. This is real outbound network usage — not offline-only.
- **Windows** `Updater.cs` can download via `HttpClient` but the menu action is not connected yet.
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