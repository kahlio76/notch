import AppKit
import NotchCore
import SwiftUI

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
            Color.black
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
                Color.clear.transition(.notchContent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: NotchStore.panelWidth)
    }
}

