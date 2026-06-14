import SwiftUI

struct FooterView: View {
    @EnvironmentObject private var manager: SignatureManager
    @State private var showAbout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            // Row 1: Toggles
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { manager.launchAtLogin },
                    set: { manager.setLaunchAtLogin($0) }
                )) {
                    Text("Launch at Login")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel("Launch Ponten at login")
                
                Toggle(isOn: $manager.autoPaste) {
                    Text("Auto-paste after copying")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel("Automatically paste signature after copying")
                .onChange(of: manager.autoPaste) { newValue in
                    if newValue {
                        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
                        let accessEnabled = AXIsProcessTrustedWithOptions(options)
                        if !accessEnabled {
                            manager.showToast("Please allow Accessibility access in System Settings")
                            // Removing the forced toggle-off so users don't have to click twice after granting permission
                            // manager.autoPaste = false
                        }
                    }
                }
            }

            // Row 2: Shortcut Settings
            HStack {
                Text("Global Shortcut:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $manager.globalShortcut) {
                    ForEach(ShortcutChoice.allCases) { choice in
                        Text(choice.description).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 60)
            }
            
            Divider()
                .padding(.vertical, 2)

            // Row 3: Action Buttons
            HStack {
                Button("Check for Updates") {
                    NotificationCenter.default.post(name: NSNotification.Name("CheckForUpdates"), object: nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityLabel("Check for Updates")
                
                Spacer()
                
                Button(action: { showAbout = true }) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About Ponten")
                .popover(isPresented: $showAbout, arrowEdge: .bottom) {
                    AboutView()
                }
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel("Quit Ponten")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
