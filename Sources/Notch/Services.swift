import AppKit
import AudioToolbox
import Carbon.HIToolbox
import CoreAudio
import IOKit.ps
import NotchCore

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

