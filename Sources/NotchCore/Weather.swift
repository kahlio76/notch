import Foundation

/// SF Symbol and label for a WMO weather code, as returned by Open-Meteo.
public func weatherStyle(code: Int, isDay: Bool) -> (symbol: String, label: String) {
    switch code {
    case 0: return (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
    case 1, 2: return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
    case 3: return ("cloud.fill", "Cloudy")
    case 45, 48: return ("cloud.fog.fill", "Fog")
    case 51...57: return ("cloud.drizzle.fill", "Drizzle")
    case 61...67, 80...82: return ("cloud.rain.fill", "Rain")
    case 71...77, 85, 86: return ("cloud.snow.fill", "Snow")
    case 95...99: return ("cloud.bolt.rain.fill", "Storm")
    default: return ("cloud.fill", "—")
    }
}
