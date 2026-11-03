import AppKit
import NotchCore
import ServiceManagement
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
            if surface == .wings { WingsView(store: store).transition(contentTransition) }
            if surface == .peek, let peek = store.peek { PeekView(peek: peek, top: store.notchHeight).transition(contentTransition) }
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

// MARK: Compact

struct WingsView: View {
    @ObservedObject var store: NotchStore

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if store.track != nil, store.isPlaying {
                    ArtworkView(image: store.artwork, corner: 5).frame(width: 22, height: 22)
                }
            }
            .frame(width: 42)
            Spacer(minLength: store.notchWidth)
            Group {
                if store.claudeWorking {
                    PixelGrid(state: .working, cell: 2.5, gap: 1)
                } else if store.isPlaying {
                    EqualizerBars()
                }
            }
            .frame(width: 42)
        }
        .frame(height: store.notchHeight)
    }
}

struct PeekView: View {
    let peek: Peek
    let top: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            if let icon = peek.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else if let symbol = peek.symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            Text(peek.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
            Text(peek.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
        }
        .lineLimit(1)
        .padding(.top, top + 7)
    }
}

// MARK: Panel

struct PanelView: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            TopRow(store: store).frame(height: store.notchHeight)
            switch store.surface {
            case .done:
                DoneCard(store: store).transition(.notchContent)
            default:
                WidgetsView(store: store).transition(.notchContent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: NotchStore.panelWidth)
    }
}

struct TopRow: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let matte = Matte(scheme: scheme)
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                SettingsMenu(color: matte.secondary)
                IconButton(symbol: "speaker.wave.2", color: store.activeSlider == .volume ? matte.primary : matte.secondary, help: "Volume") {
                    store.volume = SystemControls.volume()
                    store.activeSlider = store.activeSlider == .volume ? nil : .volume
                }
                if SystemControls.hasBrightness {
                    IconButton(symbol: "sun.max", color: store.activeSlider == .brightness ? matte.primary : matte.secondary, help: "Brightness") {
                        store.brightness = SystemControls.brightness()
                        store.activeSlider = store.activeSlider == .brightness ? nil : .brightness
                    }
                }
                IconButton(symbol: "circle.lefthalf.filled", color: matte.secondary, help: "Switch the Mac between dark and light") {
                    SystemControls.toggleDarkMode()
                }
            }
            Spacer(minLength: store.notchWidth + 8)
            HStack(spacing: 10) {
                ForEach(store.pinnedApps, id: \.self) { AppButton(bundleID: $0) }
            }
        }
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

struct SettingsMenu: View {
    let color: Color
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
            Button("Edit Settings File…") { NSWorkspace.shared.open(URL(fileURLWithPath: Config.path)) }
            Divider()
            Button("Quit Notch") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(color)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct AppButton: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Button {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } label: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(url.deletingPathExtension().lastPathComponent)
        }
    }
}

struct WidgetsView: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let matte = Matte(scheme: scheme)
        VStack(spacing: 0) {
            if let slider = store.activeSlider {
                SliderRow(store: store, kind: slider).frame(height: 32)
            }
            HStack(spacing: 8) {
                MusicCard(store: store)
                WeatherCard(weather: store.weather)
            }
            .frame(height: 104)
            .padding(.top, 8)
            if store.track != nil {
                LyricsView(store: store, matte: matte).frame(height: 50)
            }
        }
    }
}

struct SliderRow: View {
    @ObservedObject var store: NotchStore
    let kind: ControlSlider
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind == .volume ? "speaker.fill" : "sun.min.fill")
                .font(.system(size: 11)).foregroundStyle(Matte(scheme: scheme).secondary).frame(width: 16)
            Slider(value: kind == .volume
                ? Binding(get: { store.volume }, set: { store.volume = $0; SystemControls.setVolume($0) })
                : Binding(get: { store.brightness }, set: { store.brightness = $0; SystemControls.setBrightness($0) }),
                in: 0...1)
                .controlSize(.small)
        }
        .padding(.horizontal, 6)
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

struct LyricsView: View {
    @ObservedObject var store: NotchStore
    let matte: Matte

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let index = lyricIndex(in: store.lyrics, at: store.position)
            let current = index.map { store.lyrics[$0].text } ?? ""
            let nextIndex = (index ?? -1) + 1
            let next = nextIndex < store.lyrics.count ? store.lyrics[nextIndex].text : ""
            VStack(spacing: 3) {
                if store.lyrics.isEmpty {
                    Text("No synced lyrics for this song").font(.system(size: 12)).foregroundStyle(matte.tertiary)
                } else {
                    Text(current.isEmpty ? "♪" : current)
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(matte.primary)
                        .id(current).transition(.opacity)
                    Text(next).font(.system(size: 12)).foregroundStyle(matte.tertiary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: current)
        }
    }
}

// MARK: Claude cards

struct DoneCard: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let matte = Matte(scheme: scheme)
        if let done = store.done {
            HStack(spacing: 14) {
                PixelGrid(state: .done, cell: 6, gap: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(done.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(matte.primary)
                    Text(done.detail).font(.system(size: 12)).foregroundStyle(matte.secondary)
                    Text(done.project).font(.system(size: 11)).foregroundStyle(matte.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }
}

// MARK: Small animations

enum PixelState { case working, waiting, done }

struct PixelGrid: View {
    let state: PixelState
    let cell: CGFloat
    let gap: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: state == .done ? 60 : 0.11)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.11)
            let size = cell * 5 + gap * 4
            Canvas { graphics, _ in
                for row in 0..<5 {
                    for column in 0..<5 {
                        let rect = CGRect(x: CGFloat(column) * (cell + gap), y: CGFloat(row) * (cell + gap), width: cell, height: cell)
                        let (color, opacity) = style(row: row, column: column, tick: tick)
                        graphics.fill(Path(roundedRect: rect, cornerRadius: cell * 0.2), with: .color(color.opacity(opacity)))
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func style(row: Int, column: Int, tick: Int) -> (Color, Double) {
        switch state {
        case .done:
            return (Color(red: 0.36, green: 0.83, blue: 0.55), 0.95)
        case .waiting:
            let amber = Color(red: 0.98, green: 0.8, blue: 0.36)
            let hash = (row * 7 + column * 13) % 11
            let phase = (tick + hash * 3) % 22
            return phase < 4 ? (amber, 1 - Double(phase) * 0.2) : (Color.gray, 0.22)
        case .working:
            // A short tail running around the outer ring.
            let ring = [(0,0),(0,1),(0,2),(0,3),(0,4),(1,4),(2,4),(3,4),(4,4),(4,3),(4,2),(4,1),(4,0),(3,0),(2,0),(1,0)]
            let orange = Color(red: 0.85, green: 0.47, blue: 0.34)
            if let position = ring.firstIndex(where: { $0 == (row, column) }) {
                let distance = (tick - position + 160) % ring.count
                return distance < 5 ? (orange, 1 - Double(distance) * 0.18) : (Color.gray, 0.28)
            }
            return (Color.gray, 0.16)
        }
    }
}

struct EqualizerBars: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { bar in
                    let level = 0.5 + 0.5 * sin(t * (5 + Double(bar) * 1.7) + Double(bar) * 1.3)
                    Capsule().fill(Color.white.opacity(0.85)).frame(width: 2.5, height: 4 + 10 * level)
                }
            }
            .frame(height: 16)
            .animation(.linear(duration: 0.12), value: t)
        }
    }
}
