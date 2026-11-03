import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var window: NotchWindowController?
    private var services: [AnyObject] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bridge = ClaudeBridge(store: store)
        guard bridge.start() else {
            // Another copy already owns the socket.
            NSApp.terminate(nil)
            return
        }
        let config = Config.load()
        store.pinnedApps = config.pinnedApps
        window = NotchWindowController(store: store)
        services = [
            bridge,
            MusicService(store: store),
            AudioTap(store: store),
            WeatherService(store: store, config: config),
            PeekService(store: store),
            ApprovalHotKeys(store: store),
        ]
    }
}
