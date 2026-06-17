# Development Guide

## Version Source of Truth

Bump **all** together, then `git tag vX.Y.Z`. Current: **1.2.12**.

| Location | Key / variable |
|----------|----------------|
| `macos/Ponten/Resources/Info.plist` | `CFBundleShortVersionString` |
| `macos/Ponten.xcodeproj/project.pbxproj` | `MARKETING_VERSION` |
| `windows/PontenWPF/PontenWPF.csproj` | `<Version>`, `<AssemblyVersion>`, `<FileVersion>`, `<InformationalVersion>` |
| `windows/installer.iss` | `#define MyAppVersion` |
| `macos/install.sh` / `build-dmg.sh` | `VERSION=` |

---

## macOS (13+, Xcode 15+)

```bash
cd macos
open Ponten.xcodeproj                              # dev: ⌘B / ⌘U
./install.sh                                       # quick install → ~/Applications
xcodebuild test -project Ponten.xcodeproj -scheme Ponten \
  -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO
swift test                                         # SPM alternative
./build-dmg.sh                                     # release → dist/Ponten-X.Y.Z.dmg
```

**New Swift files:** `gem install xcodeproj && ruby add_files.rb` (repo root).

`install.sh` / `build-dmg.sh` use a manual source list — prefer Xcode for dev; update the list if using CLI scripts.

`macos/Package.swift` defines `Ponten` + `PontenTests` + `PontenE2ETests` for `swift build` / `swift test`.

### macOS E2E tests (XCTest + Accessibility)

`PontenE2ETests/` contains **5** end-to-end tests that launch the real `Ponten.app` and drive the UI via `AXUIElement`. They run **only on macOS** — not on Windows or Linux.

```bash
cd macos
xcodebuild build -project Ponten.xcodeproj -scheme Ponten -configuration Debug \
  -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Ponten.xcodeproj -scheme Ponten \
  -destination "platform=macOS,arch=arm64" -only-testing:PontenE2ETests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

E2E mode: `--e2e` or `PONTEN_E2E=1`. Isolated data dir: `--data-dir=<path>` or `PONTEN_DATA_DIR`.

---

## Windows (.NET 8)

```bash
cd windows
dotnet build Ponten.sln -c Debug
dotnet run --project PontenWPF/PontenWPF.csproj
dotnet test Ponten.sln -c Release                  # 12 unit + 5 E2E (CI command)
dotnet publish PontenWPF/PontenWPF.csproj -c Release -r win-x64 \
  --self-contained true -p:PublishSingleFile=true
```

**SDK pin:** `windows/global.json` pins SDK **8.0.408** with `rollForward: latestPatch`. CI uses `actions/setup-dotnet` with `global-json-file: windows/global.json`.

Publish produces `dist/Ponten-Windows.exe` (build intermediate for the installer).  
Release artifact: Inno Setup `windows/installer.iss` → `dist/Ponten-Setup-X.Y.Z.exe` (installer only — no portable release).

### Windows E2E tests (FlaUI + xUnit)

`PontenWPF.E2E.Tests/` contains **5** end-to-end tests that drive the real WPF UI via [FlaUI](https://github.com/FlaUI/FlaUI). They run **only on Windows** — not on macOS or Linux.

```bash
cd windows
dotnet build Ponten.sln -c Release
dotnet test Ponten.sln -c Release --filter "Category=E2E"
```

E2E mode: `--e2e` or `PONTEN_E2E=1`. Isolated data dir: `--data-dir=<path>` or `PONTEN_DATA_DIR`.

---

## When to Use What (macOS)

| Tool | Use when |
|------|----------|
| **Xcode** | Dev, debugging, CI-parity tests |
| **SPM** | Headless `swift test` |
| **install.sh** | Fast local install |
| **build-dmg.sh** | Release DMG |

## CI

`.github/workflows/ci.yml` — PRs: macOS build+unit+E2E test, Windows unit+E2E test+publish. Tags `v*`: DMG + Inno installer + GitHub Release.