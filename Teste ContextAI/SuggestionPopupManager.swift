//
//  SuggestionPopupManager.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit

final class SuggestionPopupManager {
    static let shared = SuggestionPopupManager()
    private var panel: NSPanel?

    private init() {}

    @MainActor
    func present(text: String) {
        let contentView = SuggestionPopupView(text: text) { [weak self] in
            self?.close()
        }

        let hosting = NSHostingView(rootView: contentView)
        let size = NSSize(width: 360, height: 120)

        if panel == nil {
            let style: NSWindow.StyleMask = [.nonactivatingPanel, .titled]
            let newPanel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: style,
                                   backing: .buffered,
                                   defer: false)
            newPanel.title = "Sugestão da IA"
            newPanel.hidesOnDeactivate = false
            newPanel.isFloatingPanel = true
            newPanel.level = .statusBar
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isReleasedWhenClosed = false
            newPanel.hasShadow = true
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            panel = newPanel
        }

        panel?.contentView = hosting
        panel?.setContentSize(size)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - size.width - 16
            let y = screenFrame.maxY - size.height - 40
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel?.orderFrontRegardless()

        // Auto dismiss after a few seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.close()
        }
    }

    @MainActor
    func close() {
        panel?.orderOut(nil)
    }
}

private struct SuggestionPopupView: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sugestão da IA")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Ok", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 12)
        .frame(width: 360, height: 120)
    }
}

#endif


