import SwiftUI

@main
struct PontenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu-bar-only app.
        Settings { EmptyView() }
    }
}
