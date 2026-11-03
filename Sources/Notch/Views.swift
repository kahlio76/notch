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

extension AnyTransition {
    static var notchContent: AnyTransition { .opacity }
}

struct RootView: View {
    @ObservedObject var store: NotchStore
    @Environment(\.colorScheme) private var scheme

    private var motion: Animation { .spring(response: 0.36, dampingFraction: 0.84) }

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

