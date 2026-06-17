# Development Guide

## Version Source of Truth

Bump **all** together, then `git tag vX.Y.Z`. Current: **1.2.12**.

| Location | Key / variable |
|----------|----------------|
| `macos/Ponten/Resources/Info.plist` | `CFBundleShortVersionString` |
| `macos/Ponten.xcodeproj/project.pbxproj` | `MARKETING_VERSION` |
| `windows/PontenWPF/PontenWPF.csproj` | `<Version>`, `<AssemblyVersion>`, `<FileVersion>` |
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

`macos/Package.swift` defines `Ponten` + `PontenTests` for `swift build` / `swift test`.

---

## Windows (.NET 8)

```bash
cd windows
dotnet build Ponten.sln -c Debug
dotnet run --project PontenWPF/PontenWPF.csproj
dotnet test Ponten.sln -c Release                  # CI command
dotnet publish PontenWPF/PontenWPF.csproj -c Release -r win-x64 \
  --self-contained true -p:PublishSingleFile=true
```

Installer: Inno Setup `windows/installer.iss` → `dist/Ponten-Setup-X.Y.Z.exe` (Windows only).

---

## When to Use What (macOS)

| Tool | Use when |
|------|----------|
| **Xcode** | Dev, debugging, CI-parity tests |
| **SPM** | Headless `swift test` |
| **install.sh** | Fast local install |
| **build-dmg.sh** | Release DMG |

## CI

`.github/workflows/ci.yml` — PRs: macOS build+test, Windows test+publish. Tags `v*`: DMG + Inno installer + GitHub Release.