import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var window: NotchWindowController?
    private var services: [AnyObject] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = Config.load()
        window = NotchWindowController(store: store)
        services = [
            MusicService(store: store),
            WeatherService(store: store, config: config),
        ]
    }
}
