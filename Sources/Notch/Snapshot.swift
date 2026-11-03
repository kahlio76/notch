import AppKit
import NotchCore
import SwiftUI

/// `Notch --snapshot <dir>` renders every surface to PNGs with demo data, without
/// touching Spotify, the socket or the real window. Used to check the layout.
@MainActor
enum Snapshot {
    static func run(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let art = NSImage(size: NSSize(width: 80, height: 80), flipped: false) { rect in
            NSColor.systemIndigo.setFill(); rect.fill()
            return true
        }
        func demo() -> NotchStore {
            let store = NotchStore()
            store.notchHeight = 37
            store.pinnedApps = Config().pinnedApps
            store.track = Track(id: "1", name: "Low Tide", artist: "Nova Lane", album: "", duration: 200, artURL: "")
            store.isPlaying = true
            store.artwork = art
            store.lyrics = [LyricLine(time: 0, text: "Blue on blue, the harbor hums"), LyricLine(time: 999, text: "Low tide, low tide, here it comes")]
            store.positionAnchor = (1, Date())
            store.weather = WeatherNow(city: "Cupertino", temperature: 60, high: 61, low: 55, symbol: "cloud.rain.fill", label: "Rain")
            return store
        }
        var cases: [(String, NotchStore)] = []
        let widgets = demo(); widgets.hovering = true
        cases.append(("widgets", widgets))
        let empty = demo(); empty.hovering = true; empty.track = nil; empty.isPlaying = false; empty.activeSlider = .volume; empty.volume = 0.6
        cases.append(("empty-slider", empty))
        let request = demo()
        request.add(ApprovalRequest(id: UUID(), sessionID: "s", summary: "vercel deploy --prod && rm -rf ./build && echo a much longer command that has to wrap onto more than one line so it scrolls", project: "portfolio", respond: { _ in }, cancel: {}))
        cases.append(("request", request))
        let done = demo(); done.done = DoneBanner(title: "Done in 10 s", detail: "2 files changed", project: "portfolio")
        cases.append(("done", done))
        let peek = demo(); peek.peek = Peek(symbol: "bolt.fill", icon: nil, title: "Charging", detail: "82%")
        cases.append(("peek", peek))
        let wings = demo(); wings.sessions["s"] = ClaudeSession(project: "x", startedAt: Date())
        cases.append(("wings", wings))

        for (name, store) in cases {
            for (schemeName, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
                let size = store.surfaceSize
                let view = RootView(store: store)
                    .environment(\.colorScheme, scheme)
                    .frame(width: size.width + store.topRadius * 2, height: size.height)
                    .background(Color(red: 0.4, green: 0.45, blue: 0.55))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: URL(fileURLWithPath: "\(directory)/\(name)-\(schemeName).png"))
            }
        }
    }
}
