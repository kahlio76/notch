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
    private var monitors: [Any] = []
    /// The pending hover step: first the nudge, then the full open.
    private var hoverWork: DispatchWorkItem?
    private var leaveWork: DispatchWorkItem?
    private let shadowRoom: CGFloat = 24
    private let tallestPanel: CGFloat = 214
    private let nudgeDelay = 0.12
    private let openDelay = 0.3

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

        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateMouseThrough() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.readScreen()
                self?.placeWindow()
            }
            .store(in: &subscriptions)

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in self?.mouseMoved() }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.mouseMoved()
            return event
        }) {
            monitors.append(local)
        }
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

    /// The drawn shape in screen coordinates, including its flared top corners.
    private var shapeRect: NSRect {
        let screen = self.screen.frame
        let size = store.surfaceSize
        let width = size.width + store.topRadius * 2
        return NSRect(x: screen.midX - width / 2, y: screen.maxY - size.height, width: width, height: size.height + 2)
    }

    private func updateMouseThrough() {
        let through = !shapeRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != through { panel.ignoresMouseEvents = through }
    }

    private func schedule(after delay: Double, _ step: @escaping () -> Void) {
        let work = DispatchWorkItem(block: step)
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHover() {
        hoverWork?.cancel()
        hoverWork = nil
        if store.nudged { store.nudged = false }
    }

    private func mouseMoved() {
        updateMouseThrough()
        let mouse = NSEvent.mouseLocation
        let screen = self.screen.frame
        let size = store.surfaceSize
        let shape = NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
                           width: size.width, height: size.height + 2)
        if store.hovering || store.surface == .request {
            let inside = shape.insetBy(dx: -14, dy: -14).contains(mouse)
            if inside {
                leaveWork?.cancel()
                leaveWork = nil
            } else if store.hovering, leaveWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.store.hovering = false
                    self?.store.activeSlider = nil
                    self?.leaveWork = nil
                }
                leaveWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
            cancelHover()
            return
        }
        if shape.insetBy(dx: -4, dy: 0).contains(mouse) {
            guard hoverWork == nil else { return }
            schedule(after: nudgeDelay) { [weak self] in
                guard let self else { return }
                self.store.nudged = true
                self.schedule(after: self.openDelay) { [weak self] in
                    guard let self else { return }
                    self.hoverWork = nil
                    self.store.nudged = false
                    self.store.hovering = true
                    self.store.volume = SystemControls.volume()
                    self.store.brightness = SystemControls.brightness()
                }
            }
        } else {
            cancelHover()
        }
    }
}
