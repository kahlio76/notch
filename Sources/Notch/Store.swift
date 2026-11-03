import AppKit
import Combine
import NotchCore

enum Surface: Equatable { case idle, wings, peek, widgets, request, done }

struct WeatherNow: Equatable {
    var city: String
    var temperature: Int
    var high: Int
    var low: Int
    var symbol: String
    var label: String
}

/// All state the notch draws. Touched only on the main thread.
final class NotchStore: ObservableObject {
    static let panelWidth: CGFloat = 620

    @Published var notchWidth: CGFloat = 185
    @Published var notchHeight: CGFloat = 32
    @Published var hovering = false
    /// The mouse has rested on the notch but hasn't stayed long enough to open it.
    @Published var nudged = false


    @Published var weather: WeatherNow?



    var surface: Surface {
        if hovering { return .widgets }
        return .idle
    }

    var surfaceSize: CGSize {
        let nudge: CGFloat = nudged ? 1 : 0
        switch surface {
        case .idle: return CGSize(width: notchWidth + 12 * nudge, height: notchHeight + 8 * nudge)
        case .wings: return CGSize(width: notchWidth + 84 + 12 * nudge, height: notchHeight + 8 * nudge)
        case .peek: return CGSize(width: max(notchWidth + 40, 240) + 12 * nudge, height: notchHeight + 34 + 8 * nudge)
        case .widgets:
            let slider: CGFloat = 0
            let lyricsArea: CGFloat = 0
            return CGSize(width: Self.panelWidth, height: notchHeight + 8 + 104 + slider + lyricsArea + 14)
        case .request: return CGSize(width: Self.panelWidth, height: notchHeight + 118)
        case .done: return CGSize(width: Self.panelWidth, height: notchHeight + 76)
        }
    }

    var isPanel: Bool { [.widgets, .request, .done].contains(surface) }
    /// How far the shape flares out where it meets the top of the screen.
    var topRadius: CGFloat { isPanel ? 19 : 6 }
    var bottomRadius: CGFloat { isPanel ? 24 : 14 }

}
