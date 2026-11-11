import AppKit
import SwiftUI

struct HUDContentView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
    }
}

/// Short, non-activating floating message used for errors and permission hints.
final class HUDWindow: NSPanel {
    private static var current: HUDWindow?

    static func show(_ text: String, duration: TimeInterval = 2.1) {
        DispatchQueue.main.async {
            current?.orderOut(nil)
            current = nil

            let hosting = NSHostingView(rootView: HUDContentView(text: text))
            let size = hosting.fittingSize
            let sizeForFrame = NSSize(width: max(size.width, 80), height: max(size.height, 32))

            let panel = HUDWindow(
                contentRect: NSRect(origin: .zero, size: sizeForFrame),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.isMovable = false
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .stationary]
            panel.contentView = hosting

            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                let origin = NSPoint(
                    x: visible.midX - sizeForFrame.width / 2,
                    y: visible.maxY - sizeForFrame.height - 24
                )
                panel.setFrameOrigin(origin)
            }

            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }

            current = panel

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    panel.orderOut(nil)
                    if current === panel { current = nil }
                })
            }
        }
    }
}
