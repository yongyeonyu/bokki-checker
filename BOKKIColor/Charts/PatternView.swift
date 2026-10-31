import SwiftUI
import CoreGraphics

/// Builds 16-bit-per-channel CGImages so ramps are rendered with no 8-bit banding.
enum RampImage {
    static func make(width: Int, height: Int, space: OutputSpace, pixel: (Int, Int) -> Vec3) -> CGImage? {
        let cs = CGColorSpace(name: space.displaySpace == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
        var buf = [UInt16](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var v = pixel(x, y)
                // Rec.709 pixels are BT.709 signal values; convert to the sRGB curve the screen uses.
                if space == .rec709 {
                    v = Vec3(ColorMath.encodeSRGB(ColorMath.decodeRec709(v.x)), ColorMath.encodeSRGB(ColorMath.decodeRec709(v.y)),
                             ColorMath.encodeSRGB(ColorMath.decodeRec709(v.z)))
                }
                let o = (y * width + x) * 4
                buf[o] = UInt16(max(0, min(1, v.x)) * 65535)
                buf[o + 1] = UInt16(max(0, min(1, v.y)) * 65535)
                buf[o + 2] = UInt16(max(0, min(1, v.z)) * 65535)
                buf[o + 3] = 65535
            }
        }
        let data = Data(bytes: buf, count: buf.count * 2) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Horizontal bands of smooth 0→1 ramps; each band is a channel mask.
    static func bands(_ masks: [Vec3], space: OutputSpace) -> CGImage? {
        make(width: 4096, height: masks.count, space: space) { x, y in masks[y] * (Double(x) / 4095) }
    }

    static func hueWheel(size: Int, space: OutputSpace) -> CGImage? {
        let c = Double(size) / 2
        return make(width: size, height: size, space: space) { x, y in
            let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c
            let r = sqrt(dx * dx + dy * dy) / c
            guard r <= 1 else { return Vec3(0, 0, 0) }
            let h = (atan2(-dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1) * 6
            let k = Vec3(5, 3, 1)
            // HSV (V = 1) → RGB, saturation = radius.
            let rgb = Vec3((k.x + h).truncatingRemainder(dividingBy: 6), (k.y + h).truncatingRemainder(dividingBy: 6), (k.z + h).truncatingRemainder(dividingBy: 6))
            func f(_ n: Double) -> Double { 1 - r * max(0, min(min(n, 4 - n), 1)) }
            return Vec3(f(rgb.x), f(rgb.y), f(rgb.z))
        }
    }
}

struct PatternView: View {
    let kind: PatternKind
    let space: OutputSpace
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
        }
        .background(Color.black)
        .accessibilityIgnoresInvertColors()
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        switch kind {
        case .grayRamp:
            rampStack([Vec3(1, 1, 1)], ticks: true)
        case .rgbRamps:
            rampStack([Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1), Vec3(1, 1, 1)], ticks: true)
        case .steppedRamp32:
            Canvas { ctx, s in
                let w = s.width / 32
                for i in 0..<32 {
                    let v = Double(i * 255 / 31) / 255
                    ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w + 0.5, height: s.height)), with: .color(ColorSpec.gray(v).color(in: space)))
                }
            }
        case .hueWheel:
            if let img = RampImage.hueWheel(size: 768, space: space) {
                Image(decorative: img, scale: 1).resizable().interpolation(.high).aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .smpteBars:
            Canvas { ctx, s in drawSMPTE(ctx, s) }
        case .siemensStar:
            Canvas { ctx, s in drawStar(ctx, s) }
        case .slantedEdge:
            Canvas { ctx, s in drawEdges(ctx, s) }
        case .linePairs:
            Canvas { ctx, s in drawLinePairs(ctx, s) }
        case .checkerboard:
            Canvas { ctx, s in drawChecker(ctx, s) }
        case .distortionGrid:
            Canvas { ctx, s in drawGrid(ctx, s) }
        }
    }

    private func rampStack(_ masks: [Vec3], ticks: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(masks.enumerated()), id: \.offset) { _, m in
                if let img = RampImage.bands([m], space: space) {
                    Image(decorative: img, scale: 1).resizable().interpolation(.high)
                }
            }
            if ticks {
                Canvas { ctx, s in
                    for i in 0...10 {
                        let x = s.width * CGFloat(i) / 10
                        ctx.fill(Path(CGRect(x: min(x, s.width - 1), y: 0, width: 1, height: s.height * 0.4)), with: .color(.white))
                        ctx.draw(Text("\(i * 10)%").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white),
                                 at: CGPoint(x: min(max(x, 16), s.width - 16), y: s.height * 0.7))
                    }
                }
                .frame(height: 28)
            }
        }
    }

    private func px(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
    private func c(_ r: Double, _ g: Double, _ b: Double) -> GraphicsContext.Shading {
        .color(ColorSpec.encoded(Vec3(r, g, b), space: .sRGB).color(in: space))
    }

    /// Video signal levels (bars are defined as Rec.709 code values).
    private func v709(_ r: Double, _ g: Double, _ b: Double) -> GraphicsContext.Shading {
        .color(ColorSpec.encoded(Vec3(r, g, b), space: .rec709).color(in: space))
    }

    private func drawSMPTE(_ ctx: GraphicsContext, _ s: CGSize) {
        let w = s.width / 7
        let top: [(Double, Double, Double)] = [(0.75, 0.75, 0.75), (0.75, 0.75, 0), (0, 0.75, 0.75), (0, 0.75, 0), (0.75, 0, 0.75), (0.75, 0, 0), (0, 0, 0.75)]
        let mid: [(Double, Double, Double)] = [(0, 0, 0.75), (0.075, 0.075, 0.075), (0.75, 0, 0.75), (0.075, 0.075, 0.075), (0, 0.75, 0.75), (0.075, 0.075, 0.075), (0.75, 0.75, 0.75)]
        let h1 = s.height * 0.67, h2 = s.height * 0.08
        for i in 0..<7 {
            ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w + 0.5, height: h1)), with: v709(top[i].0, top[i].1, top[i].2))
            ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: h1, width: w + 0.5, height: h2)), with: v709(mid[i].0, mid[i].1, mid[i].2))
        }
        // Bottom: -I, 100% white, +Q, black, PLUGE (-4/0/+4 %), black.
        let y = h1 + h2, h = s.height - y
        let black = 0.075
        let parts: [(CGFloat, (Double, Double, Double))] = [
            (1.25, (0, 0.129, 0.298)), (1.25, (1, 1, 1)), (1.25, (0.196, 0, 0.416)), (1.25, (black, black, black)),
            (1 / 3, (0.035, 0.035, 0.035)), (1 / 3, (black, black, black)), (1 / 3, (0.115, 0.115, 0.115)), (1, (black, black, black)),
        ]
        var x: CGFloat = 0
        for (units, col) in parts {
            ctx.fill(Path(CGRect(x: x, y: y, width: units * w + 0.5, height: h)), with: v709(col.0, col.1, col.2))
            x += units * w
        }
    }

    private func drawStar(_ ctx: GraphicsContext, _ s: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: c(1, 1, 1))
        let center = CGPoint(x: s.width / 2, y: s.height / 2)
        let r = min(s.width, s.height) * 0.47
        let spokes = 72
        var path = Path()
        for i in stride(from: 0, to: spokes, by: 2) {
            let a0 = Double(i) / Double(spokes) * 2 * .pi, a1 = Double(i + 1) / Double(spokes) * 2 * .pi
            path.move(to: center)
            path.addArc(center: center, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            path.closeSubpath()
        }
        ctx.fill(path, with: c(0, 0, 0))
        ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: c(0, 0, 0), lineWidth: 2)
    }

    private func drawEdges(_ ctx: GraphicsContext, _ s: CGSize) {
        // ISO 12233 e-SFR style: ~4:1 contrast edges tilted 5° on a mid-gray field.
        let light = ColorMath.encodeSRGB(0.72), dark = ColorMath.encodeSRGB(0.18)
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: c(light, light, light))
        let m = min(s.width, s.height)
        let centers = [CGPoint(x: s.width / 2, y: s.height / 2), CGPoint(x: s.width * 0.15, y: s.height * 0.18), CGPoint(x: s.width * 0.85, y: s.height * 0.18),
                       CGPoint(x: s.width * 0.15, y: s.height * 0.82), CGPoint(x: s.width * 0.85, y: s.height * 0.82)]
        for (i, p) in centers.enumerated() {
            let side = i == 0 ? m * 0.36 : m * 0.16
            var t = ctx
            t.translateBy(x: p.x, y: p.y)
            t.rotate(by: .degrees(5))
            t.fill(Path(CGRect(x: -side / 2, y: -side / 2, width: side, height: side)), with: c(dark, dark, dark))
        }
    }

    private func drawLinePairs(_ ctx: GraphicsContext, _ s: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: c(0.5, 0.5, 0.5))
        let widths = [1, 2, 3, 4]
        let cellW = s.width / CGFloat(widths.count), cellH = s.height / 2
        for (i, wpx) in widths.enumerated() {
            let lw = CGFloat(wpx) / scale
            for row in 0..<2 {
                let box = CGRect(x: px(CGFloat(i) * cellW + cellW * 0.1), y: px(CGFloat(row) * cellH + cellH * 0.12),
                                 width: px(cellW * 0.8), height: px(cellH * 0.72))
                ctx.fill(Path(box), with: c(1, 1, 1))
                var p = Path()
                if row == 0 {
                    var x = box.minX
                    while x < box.maxX { p.addRect(CGRect(x: x, y: box.minY, width: lw, height: box.height)); x += 2 * lw }
                } else {
                    var y = box.minY
                    while y < box.maxY { p.addRect(CGRect(x: box.minX, y: y, width: box.width, height: lw)); y += 2 * lw }
                }
                ctx.fill(p, with: c(0, 0, 0))
                ctx.draw(Text("\(wpx) px").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white),
                         at: CGPoint(x: box.midX, y: CGFloat(row) * cellH + cellH * 0.06))
            }
        }
    }

    private func drawChecker(_ ctx: GraphicsContext, _ s: CGSize) {
        let side = px(min(s.width, s.height) / 12)
        let cols = Int(ceil(s.width / side)), rows = Int(ceil(s.height / side))
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: c(1, 1, 1))
        var p = Path()
        for r in 0..<rows { for col in 0..<cols where (r + col) % 2 == 0 {
            p.addRect(CGRect(x: CGFloat(col) * side, y: CGFloat(r) * side, width: side, height: side))
        } }
        ctx.fill(p, with: c(0, 0, 0))
    }

    private func drawGrid(_ ctx: GraphicsContext, _ s: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: c(0, 0, 0))
        let step = px(min(s.width, s.height) / 16)
        let lw = 2 / scale
        let center = CGPoint(x: px(s.width / 2), y: px(s.height / 2))
        var p = Path()
        var x = center.x.truncatingRemainder(dividingBy: step)
        while x < s.width { p.addRect(CGRect(x: x, y: 0, width: lw, height: s.height)); x += step }
        var y = center.y.truncatingRemainder(dividingBy: step)
        while y < s.height { p.addRect(CGRect(x: 0, y: y, width: s.width, height: lw)); y += step }
        ctx.fill(p, with: c(1, 1, 1))
        for k in 1...3 {
            let r = min(s.width, s.height) * 0.15 * CGFloat(k)
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: c(1, 0.2, 0.2), lineWidth: lw)
        }
    }
}
