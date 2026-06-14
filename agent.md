# Personal Signature - AI Agent Guidelines

Welcome to the **Personal Signature** project! This document serves as a comprehensive guide for any AI Agent working on this repository. Please read and follow these rules strictly before modifying code or pushing changes.

## 1. Project Architecture
- **100% Native**: This project uses purely native AppKit and SwiftUI for macOS.
- **No Storyboards/XIBs**: All views are constructed programmatically using SwiftUI.
- **Menu Bar Exclusive**: This is a Menu Bar (`LSUIElement`) application. There is no main window. The primary entry point is `MenuBarView` presented via an `NSPopover`.
- **No 3rd-Party Dependencies**: We removed Sparkle and KeyboardShortcuts in favor of native implementations. Do not add external Swift packages unless explicitly requested by the user.
- **Data Flow**: We heavily use `NotificationCenter` for cross-component events (like triggering updates) since `NSApp.delegate` can sometimes be inaccessible from SwiftUI's Proxy Adaptor.

## 2. Strict Workflow Rules (CRITICAL)

To prevent mistakes and ensure high-quality contributions, you must follow this workflow:

1. **Plan Before Executing**: Ensure you understand the full scope of the user's request.
2. **Implement & Test**: Write the code and run `./install.sh` to compile and verify that the app successfully builds. Do not skip testing.
3. **Update Documentation FIRST**: 
   - Open `README.md` and check if the **Roadmap & Completed Features** section needs to be updated.
   - If you completed a roadmap item, move it to the ✅ **Completed** section.
   - Ensure the `README.md` accurately reflects the new state of the application.
4. **Final Double Check**: Review all your changes to ensure you haven't forgotten any sub-tasks (e.g., updating docs, running scripts).
5. **Commit & Push**: Only AFTER documentation is updated and the build is verified should you commit and push to Git.

## 3. Notable Features
If you are modifying existing features, be aware of how they work:
- **Native Auto-Updater**: Uses `URLSession` to fetch the latest release from the GitHub API, downloads the zip to a temporary directory, replaces the current bundle, and restarts the app.
- **Auto-Paste**: Uses macOS Accessibility APIs (`AXUIElement`) to simulate `Cmd+V`.
- **Background Removal**: Uses CoreImage (`CIColorCube`) to strip white backgrounds natively.
- **Built-in Drawing**: Uses SwiftUI `Canvas` and `DragGesture` to draw paths, rendered natively to an `NSImage` via `ImageRenderer`.
- **Global Shortcuts**: Implemented using Carbon APIs (`RegisterEventHotKey`).

## 4. Attitude and Tone
- Be extremely thorough and meticulous ("teliti").
- Always double-check your work before concluding your task.
- If something breaks, fix it immediately without waiting for the user to point it out.
