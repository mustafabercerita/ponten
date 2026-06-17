# Contributing to Ponten

Thank you for contributing! Ponten is a small, native cross-platform app — keep changes focused and tested.

## Before You Start

- Read [`agent.md`](agent.md) for architecture, naming conventions, and AI/human dev rules.
- Read [`DEVELOPMENT.md`](DEVELOPMENT.md) for build and test commands.

## Branch Naming

| Prefix | Use |
|--------|-----|
| `feature/` | New functionality |
| `fix/` | Bug fixes |
| `refactor/` | Code structure, no behavior change |
| `docs/` | Documentation only |

Example: `feature/windows-auto-update`, `fix/macos-clipboard-png`

## Development Flow

1. Fork the repo and create a branch from `main`.
2. Make your changes on the appropriate platform(s).
3. **Run tests locally** before opening a PR:
   - macOS: `cd macos && xcodebuild test …` or `swift test` (see `DEVELOPMENT.md`)
   - Windows: `cd windows && dotnet test Ponten.sln -c Release`
4. If you added macOS `.swift` files, run `ruby add_files.rb` from the repo root.
5. Update `README.md` / `CHANGELOG.md` if user-facing behavior changed.
6. Open a PR against `main` with a clear description and test notes.

## Pull Request Requirements

- [ ] Builds on the platform(s) you touched
- [ ] Tests pass locally
- [ ] No unrelated drive-by changes
- [ ] Version numbers bumped only when releasing (see `agent.md` checklist)
- [ ] New Swift sources synced via `add_files.rb` if applicable

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every PR to `main`:

- **macOS**: compile + unit tests (`xcodebuild test`)
- **Windows**: `dotnet test Ponten.sln -c Release` + publish build

PRs must pass CI before merge. Release artifacts (DMG, installer) are produced on `v*` tags only.

## Code Style

- **macOS**: SwiftUI views in `Views/`, models in `Models/`, no storyboards.
- **Windows**: WPF XAML + code-behind; keep `MenuBarView` as the main UI surface.
- Prefer native APIs over third-party libraries (Windows: `H.NotifyIcon.Wpf` is the one exception).

## Questions?

Open a GitHub issue or discussion. For release/version questions, see the version table in `DEVELOPMENT.md`.