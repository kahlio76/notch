import AppKit
import NotchCore
import SwiftUI

struct Matte {
    let scheme: ColorScheme
    var panel: Color { scheme == .dark ? Color.black : Color(red: 0.93, green: 0.935, blue: 0.945) }
    var card: Color { scheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.85) }
    var primary: Color { scheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.86) }
    var secondary: Color { scheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5) }
    var tertiary: Color { scheme == .dark ? Color.white.opacity(0.32) : Color.black.opacity(0.3) }
}

/// The notch outline: flat along the top of the screen, flaring out at the top corners.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// A blur and fade that scales from the top edge, so content grows out of the notch.
private struct NotchContentEffect: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: hidden ? 8 : 0)
            .scaleEffect(hidden ? 0.96 : 1, anchor: .top)
            .opacity(hidden ? 0 : 1)
    }
}

extension AnyTransition {
    static var notchContent: AnyTransition {
        .modifier(active: NotchContentEffect(hidden: true), identity: NotchContentEffect(hidden: false))
    }
}

struct RootView: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    /// Critically damped, so opening and closing glide with no wobble. Only the hover nudge bounces.
    private var motion: Animation {
        if store.nudged { return .bouncy.speed(1.2) }
        return store.isPanel
            ? .spring(response: 0.42, dampingFraction: 1.0)
            : .spring(response: 0.45, dampingFraction: 1.0)
    }

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .notchContent.animation(.smooth(duration: 0.32).delay(0.06)),
            removal: .notchContent.animation(.smooth(duration: 0.16))
        )
    }

    var body: some View {
        let surface = store.surface
        let size = store.surfaceSize
        let isPanel = store.isPanel
        let shape = NotchShape(top: store.topRadius, bottom: store.bottomRadius)

        ZStack(alignment: .top) {
            (isPanel ? Matte(scheme: scheme).panel : Color.black)
            if isPanel { PanelView(store: store).transition(contentTransition) }
            // The hardware notch stays black in either theme.
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .fill(Color.black)
                .frame(width: store.notchWidth, height: store.notchHeight)
        }
        .frame(width: size.width + store.topRadius * 2, height: size.height, alignment: .top)
        .clipShape(shape)
        .background(shape.fill(Color.black.opacity(0.001)).shadow(color: .black.opacity(isPanel ? 0.3 : 0), radius: 12, y: 5))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motion, value: surface)
        .animation(motion, value: size)
    }
}

// MARK: Panel

struct PanelView: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: store.notchHeight)
            switch store.surface {
            default:
                WidgetsView(store: store).transition(.notchContent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: NotchStore.panelWidth)
    }
}

struct IconButton: View {
    let symbol: String
    let color: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct WidgetsView: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let matte = Matte(scheme: scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                MusicCard(store: store)
                WeatherCard(weather: store.weather)
            }
            .frame(height: 104)
            .padding(.top, 8)
        }
    }
}

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Matte(scheme: scheme).card))
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct MusicCard: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let matte = Matte(scheme: scheme)
        Card {
            HStack(spacing: 12) {
                ArtworkView(image: store.track == nil ? nil : store.artwork, corner: 10).frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 2) {
                    if let track = store.track {
                        Text(track.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(matte.primary)
                        Text(track.artist).font(.system(size: 12)).foregroundStyle(matte.secondary)
                    } else if store.musicNeedsPermission {
                        Text("Spotify needs permission").font(.system(size: 13, weight: .semibold)).foregroundStyle(matte.primary)
                        Text("Allow Notch under Privacy & Security → Automation").font(.system(size: 11)).foregroundStyle(matte.secondary)
                    } else {
                        Text("Nothing playing").font(.system(size: 13, weight: .semibold)).foregroundStyle(matte.primary)
                        Text(store.spotifyRunning ? "Press play in Spotify" : "Spotify isn't open").font(.system(size: 12)).foregroundStyle(matte.secondary)
                    }
                    Spacer(minLength: 0)
                    if store.track != nil {
                        HStack(spacing: 18) {
                            IconButton(symbol: "backward.fill", color: matte.primary, help: "Previous") { MusicService.send("previous track") }
                            IconButton(symbol: store.isPlaying ? "pause.fill" : "play.fill", color: matte.primary, help: "Play or pause") { MusicService.send("playpause") }
                            IconButton(symbol: "forward.fill", color: matte.primary, help: "Next") { MusicService.send("next track") }
                        }
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

struct WeatherCard: View {
    let weather: WeatherNow?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let matte = Matte(scheme: scheme)
        Card {
            if let weather {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(weather.temperature)°").font(.system(size: 30, weight: .light)).foregroundStyle(matte.primary)
                        Text(weather.city).font(.system(size: 12)).foregroundStyle(matte.secondary)
                        Spacer(minLength: 0)
                        Text("H \(weather.high)°  L \(weather.low)°").font(.system(size: 11)).foregroundStyle(matte.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: weather.symbol)
                        // The multicolor cloud is white, which vanishes on White Matte.
                        .symbolRenderingMode(scheme == .dark ? .multicolor : .hierarchical)
                        .foregroundStyle(matte.secondary)
                        .font(.system(size: 26))
                        .help(weather.label)
                }
                .lineLimit(1)
            } else {
                Text("Loading weather…").font(.system(size: 12)).foregroundStyle(matte.secondary)
            }
        }
    }
}

