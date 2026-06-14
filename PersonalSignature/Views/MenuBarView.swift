import SwiftUI
import UniformTypeIdentifiers

/// Root view rendered inside the NSPopover.
struct MenuBarView: View {
    @EnvironmentObject private var manager: SignatureManager

    @State private var showDrawing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView()

                Divider()

                Group {
                    if !manager.signatures.isEmpty {
                        SignatureActiveView(showDrawing: $showDrawing)
                    } else {
                        EmptyStateView(showDrawing: $showDrawing)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: !manager.signatures.isEmpty)

                Divider()

                FooterView()
            }
            .frame(width: 300)
            .background(Color(NSColor.windowBackgroundColor))

            // Toast notification overlay
            if let msg = manager.toastMessage {
                ToastView(message: msg)
                    .padding(.bottom, 14)
                    .zIndex(10)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .sheet(isPresented: $showDrawing) {
            DrawingView()
                .environmentObject(manager)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: manager.toastMessage)
    }
}

// Components have been extracted into:
// - HeaderView.swift
// - SignatureActiveView.swift
// - EmptyStateView.swift
// - FooterView.swift
// - AboutView.swift
