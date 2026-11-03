import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var services: [AnyObject] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        services = [
        ]
    }
}
