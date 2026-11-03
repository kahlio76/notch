import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // The default would push a borderless window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The window is a fixed size that fits the largest panel, and never resizes: resizing it
/// during an animation races SwiftUI, which then starts the shape from the window's centre.
/// It ignores the mouse whenever the cursor is outside the drawn shape, so everything
/// around the notch keeps getting its clicks.
final class NotchWindowController {
    private let store: NotchStore
    private let panel: NotchPanel
    private var subscriptions = Set<AnyCancellable>()
    private let shadowRoom: CGFloat = 24
    private let tallestPanel: CGFloat = 214

    init(store: NotchStore) {
        self.store = store
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        let host = FirstMouseHostingView(rootView: RootView(store: store))
        // Otherwise the hosting view resizes the window to fit its content.
        host.sizingOptions = []
        panel.contentView = host

        readScreen()
        placeWindow()
        panel.orderFrontRegardless()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.readScreen()
                self?.placeWindow()
            }
            .store(in: &subscriptions)

    }

    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func readScreen() {
        let screen = self.screen
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            store.notchWidth = screen.frame.width - left.width - right.width
            store.notchHeight = screen.safeAreaInsets.top
        } else {
            // A display with no notch gets a drawn one the height of its menu bar.
            store.notchWidth = 185
            store.notchHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        }
    }

    private func placeWindow() {
        let screen = self.screen.frame
        let width = NotchStore.panelWidth + (19 + shadowRoom) * 2
        let height = store.notchHeight + tallestPanel + shadowRoom
        panel.setFrame(NSRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height), display: true)
    }

}
