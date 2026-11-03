import AppKit
import AudioToolbox
import Carbon.HIToolbox
import CoreAudio
import IOKit.ps
import NotchCore

// MARK: AppleScript

/// NSAppleScript isn't thread-safe and can block on an Automation prompt, so every
/// script runs in order on this one queue, off the main thread.
enum Script {
    static let queue = DispatchQueue(label: "notch.applescript")

    static func run(_ source: String) -> (output: String?, errorNumber: Int?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return (result?.stringValue, error?[NSAppleScript.errorNumber] as? Int)
    }
}

// MARK: Music

final class MusicService {
    private let store: NotchStore
    private var timer: Timer?
    private var ticks = 0
    private let bundleID = "com.spotify.client"

    private static let separator = "\u{1F}"
    private static let readScript = """
    tell application "Spotify"
        set s to player state as string
        if s is "stopped" then return "stopped"
        set t to current track
        set art to ""
        try
            set art to artwork url of t
        end try
        set d to character id 31
        return s & d & (id of t) & d & (name of t) & d & (artist of t) & d & (album of t) & d & ((duration of t) as string) & d & ((player position) as string) & d & art
    end tell
    """

    init(store: NotchStore) {
        self.store = store
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.poll()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == self?.bundleID { self?.poll() }
            }
        }
        // Keeps lyrics in step while they're on screen; otherwise Spotify's own notification does the work.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            if self.store.surface == .widgets || self.ticks % 10 == 0 { self.poll() }
        }
        poll()
    }

    private func poll() {
        // `tell application` would launch Spotify if it were closed.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            store.spotifyRunning = false
            apply(state: nil, position: 0, track: nil)
            return
        }
        store.spotifyRunning = true
        Script.queue.async { [weak self] in
            let result = Script.run(Self.readScript)
            DispatchQueue.main.async { self?.handle(result) }
        }
    }

    private func handle(_ result: (output: String?, errorNumber: Int?)) {
        store.musicNeedsPermission = result.errorNumber == -1743
        guard let output = result.output, output != "stopped" else {
            apply(state: nil, position: 0, track: nil)
            return
        }
        let parts = output.components(separatedBy: Self.separator)
        guard parts.count == 8 else { return }
        let number = { (text: String) in Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let track = Track(id: parts[1], name: parts[2], artist: parts[3], album: parts[4],
                          duration: number(parts[5]) / 1000, artURL: parts[7])
        apply(state: parts[0], position: number(parts[6]), track: track)
    }

    private func apply(state: String?, position: Double, track: Track?) {
        if store.track != track { store.track = track }
        let playing = state == "playing"
        if store.isPlaying != playing { store.isPlaying = playing }
        guard let track else {
            return
        }
    }

}

// MARK: Weather

final class WeatherService {
    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
        let current: Current
        let daily: Daily
    }

    private let store: NotchStore
    private let config: Config
    private var timer: Timer?

    init(store: NotchStore, config: Config) {
        self.store = store
        self.config = config
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(config.latitude)),
            .init(name: "longitude", value: String(config.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "temperature_unit", value: config.fahrenheit ? "fahrenheit" : "celsius"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]
        guard let url = components.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let response = try? JSONDecoder().decode(Response.self, from: data),
                  let high = response.daily.temperature_2m_max.first, let low = response.daily.temperature_2m_min.first else { return }
            let style = weatherStyle(code: response.current.weather_code, isDay: response.current.is_day == 1)
            let now = WeatherNow(city: self.config.city, temperature: Int(response.current.temperature_2m.rounded()),
                                 high: Int(high.rounded()), low: Int(low.rounded()), symbol: style.symbol, label: style.label)
            DispatchQueue.main.async { self.store.weather = now }
        }.resume()
    }
}

