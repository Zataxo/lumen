import SwiftUI

/// The animated "neural engine" from the app icon: a breathing core, two counter-rotating
/// rings of nodes, synapses that light up, and signals travelling inward. Drawn with Canvas
/// in one pass per frame, so it stays cheap. Freezes on a still frame under Reduce Motion.
struct NeuralOrbView: View {
    var size: CGFloat = 132
    /// Tint for the core and inner ring; the outer ring stays violet like the icon.
    var tint: Color = .cyan
    /// Brighter, faster animation while the app is busy (e.g. waiting for a reply).
    var isActive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let innerCount = 6
    private static let outerCount = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0.6 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, canvasSize in
                draw(in: &canvas, size: canvasSize, time: time)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unit = min(size.width, size.height) / 2
        let speed = isActive ? 1.8 : 1.0
        let violet = Color(red: 0.65, green: 0.55, blue: 0.98)
        let glowBoost = colorScheme == .dark ? 1.0 : 0.8

        // Positions: rings counter-rotate slowly; a gentle y-squash gives a tilted, 3D feel.
        let innerRotation = time * 0.35 * speed
        let outerRotation = -time * 0.18 * speed
        func ringPoint(radius: CGFloat, angle: Double, squash: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle) * squash)
        }
        let inner = (0..<Self.innerCount).map {
            ringPoint(radius: unit * 0.42, angle: innerRotation + Double($0) * 2 * .pi / Double(Self.innerCount), squash: 0.92)
        }
        let outer = (0..<Self.outerCount).map {
            ringPoint(radius: unit * 0.78, angle: outerRotation + Double($0) * 2 * .pi / Double(Self.outerCount) + .pi / 8, squash: 0.86)
        }

        // Ambient glow.
        let breathe = 0.5 + 0.5 * sin(time * 1.6 * speed)
        canvas.fill(
            Path(ellipseIn: CGRect(x: center.x - unit, y: center.y - unit, width: unit * 2, height: unit * 2)),
            with: .radialGradient(
                Gradient(colors: [tint.opacity(0.32 * glowBoost + 0.1 * breathe), violet.opacity(0.14), .clear]),
                center: center, startRadius: 0, endRadius: unit
            )
        )

        // Outer ring outline.
        var ring = Path()
        for (index, point) in outer.enumerated() {
            index == 0 ? ring.move(to: point) : ring.addLine(to: point)
        }
        ring.closeSubpath()
        canvas.stroke(ring, with: .color(violet.opacity(0.22)), lineWidth: 1)

        // Synapses: inner → two nearest outer nodes; each pulses on its own phase.
        for (i, p) in inner.enumerated() {
            let nearest = outer.sorted { p.distance(to: $0) < p.distance(to: $1) }.prefix(2)
            for (j, q) in nearest.enumerated() {
                let phase = 0.5 + 0.5 * sin(time * 2.2 * speed + Double(i * 2 + j) * 1.3)
                var path = Path()
                path.move(to: p)
                path.addLine(to: q)
                canvas.stroke(path, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.35 + 0.45 * phase), violet.opacity(0.25 + 0.3 * phase)]),
                    startPoint: p, endPoint: q
                ), lineWidth: 1.4)
            }
        }

        // Spokes and signals travelling from the inner ring into the core.
        for (i, p) in inner.enumerated() {
            var spoke = Path()
            spoke.move(to: center)
            spoke.addLine(to: p)
            canvas.stroke(spoke, with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.75), tint.opacity(0.55)]),
                startPoint: center, endPoint: p
            ), lineWidth: 2)

            let progress = (time * 0.55 * speed + Double(i) / Double(Self.innerCount)).truncatingRemainder(dividingBy: 1)
            let signal = CGPoint(x: p.x + (center.x - p.x) * progress, y: p.y + (center.y - p.y) * progress)
            let fade = sin(progress * .pi)
            var glowing = canvas
            glowing.addFilter(.blur(radius: 2.5))
            glowing.fill(Path(ellipseIn: CGRect(x: signal.x - 3, y: signal.y - 3, width: 6, height: 6)), with: .color(.white.opacity(0.9 * fade)))
        }

        // Nodes, with a soft halo.
        func drawNode(_ point: CGPoint, radius: CGFloat, color: Color, pulse: Double) {
            var halo = canvas
            halo.addFilter(.blur(radius: radius * 1.4))
            halo.fill(Path(ellipseIn: CGRect(x: point.x - radius * 1.6, y: point.y - radius * 1.6, width: radius * 3.2, height: radius * 3.2)),
                      with: .color(color.opacity(0.35 + 0.35 * pulse)))
            canvas.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(Gradient(colors: [.white, color]),
                                              center: CGPoint(x: point.x - radius * 0.3, y: point.y - radius * 0.3),
                                              startRadius: 0, endRadius: radius * 1.2))
        }
        for (i, p) in outer.enumerated() {
            drawNode(p, radius: unit * 0.055, color: violet, pulse: 0.5 + 0.5 * sin(time * 1.9 * speed + Double(i)))
        }
        for (i, p) in inner.enumerated() {
            drawNode(p, radius: unit * 0.075, color: tint, pulse: 0.5 + 0.5 * sin(time * 2.4 * speed + Double(i) * 0.9))
        }

        // The core: breathing glow + shaded sphere.
        let coreRadius = unit * (0.24 + 0.025 * breathe)
        var coreGlow = canvas
        coreGlow.addFilter(.blur(radius: unit * 0.18))
        coreGlow.fill(Path(ellipseIn: CGRect(x: center.x - coreRadius * 1.5, y: center.y - coreRadius * 1.5, width: coreRadius * 3, height: coreRadius * 3)),
                      with: .color(tint.opacity(0.55 + 0.3 * breathe)))
        canvas.fill(Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: Color(red: 0.81, green: 0.98, blue: 1), location: 0.3),
                            .init(color: tint, location: 0.72),
                            .init(color: Color(red: 0.39, green: 0.40, blue: 0.95), location: 1),
                        ]),
                        center: CGPoint(x: center.x - coreRadius * 0.3, y: center.y - coreRadius * 0.3),
                        startRadius: 0, endRadius: coreRadius * 1.3
                    ))

        // Twinkling spark, like the icon's.
        let twinkle = max(0, sin(time * 1.3 * speed))
        if twinkle > 0.05 {
            let sparkCenter = CGPoint(x: center.x + unit * 0.6, y: center.y - unit * 0.62)
            canvas.fill(sparkle(at: sparkCenter, size: unit * 0.12 * twinkle), with: .color(.white.opacity(0.95 * twinkle)))
        }
    }

    private func sparkle(at p: CGPoint, size s: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y - s))
        path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: CGPoint(x: p.x + s * 0.12, y: p.y - s * 0.12))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: CGPoint(x: p.x + s * 0.12, y: p.y + s * 0.12))
        path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: CGPoint(x: p.x - s * 0.12, y: p.y + s * 0.12))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: CGPoint(x: p.x - s * 0.12, y: p.y - s * 0.12))
        return path
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

#Preview {
    NeuralOrbView(size: 200)
        .padding(40)
}
