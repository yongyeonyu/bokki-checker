import SwiftUI

/// Output colour space the chart is encoded in. All use D65 white, so the display emits identical
/// light for in-gamut colours whichever is chosen; what changes is the gamut and the code values.
enum OutputSpace: String, CaseIterable, Identifiable, Codable {
    case displayP3, sRGB, rec709
    var id: String { rawValue }

    var title: String {
        switch self {
        case .displayP3: "Display P3"
        case .sRGB: "sRGB"
        case .rec709: "Rec.709"
        }
    }

    /// Rec.709 code values use the BT.709 OETF; sRGB and Display P3 use the sRGB curve.
    func encode(_ v: Double) -> Double { self == .rec709 ? ColorMath.encodeRec709(v) : ColorMath.encodeSRGB(v) }
    func decode(_ v: Double) -> Double { self == .rec709 ? ColorMath.decodeRec709(v) : ColorMath.decodeSRGB(v) }

    /// Space the screen is driven in. Rec.709 shares sRGB primaries, so it is shown through the sRGB path.
    var displaySpace: OutputSpace { self == .rec709 ? .sRGB : self }

    var xyzToLinear: Mat3 { Self.matrices[self]!.inverse }
    var linearToXYZ: Mat3 { Self.matrices[self]! }

    private static let matrices: [OutputSpace: Mat3] = [
        .displayP3: ColorMath.rgbToXYZ(r: SIMD2(0.680, 0.320), g: SIMD2(0.265, 0.690), b: SIMD2(0.150, 0.060), white: ColorMath.whiteD65),
        .sRGB: ColorMath.rgbToXYZ(r: SIMD2(0.640, 0.330), g: SIMD2(0.300, 0.600), b: SIMD2(0.150, 0.060), white: ColorMath.whiteD65),
        .rec709: ColorMath.rgbToXYZ(r: SIMD2(0.640, 0.330), g: SIMD2(0.300, 0.600), b: SIMD2(0.150, 0.060), white: ColorMath.whiteD65),
    ]
}

/// A colour defined device-independently; converted to the output space at render time.
enum ColorSpec: Hashable, Codable {
    /// CIE XYZ (Y = 1 is reference white) relative to the given white point.
    case xyz(Vec3, white: SIMD2<Double>)
    /// Gamma-encoded RGB already in a specific space (0...1), e.g. video bars or hex swatches.
    case encoded(Vec3, space: OutputSpace)

    static func lab(_ l: Double, _ a: Double, _ b: Double, white: SIMD2<Double> = ColorMath.whiteD50) -> ColorSpec {
        .xyz(ColorMath.labToXYZ(Vec3(l, a, b), white: white), white: white)
    }

    static func gray(_ code: Double) -> ColorSpec { .encoded(Vec3(repeating: code), space: .sRGB) }

    static func hex(_ s: String) -> ColorSpec {
        let v = UInt32(s.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return .encoded(Vec3(Double(v >> 16 & 0xFF), Double(v >> 8 & 0xFF), Double(v & 0xFF)) / 255, space: .sRGB)
    }

    /// Linear RGB in `space`, D65-adapted, unclipped.
    func linear(in space: OutputSpace) -> Vec3 {
        switch self {
        case let .xyz(v, white):
            let d65 = white == ColorMath.whiteD65 ? v : ColorMath.adaptation(from: white, to: ColorMath.whiteD65) * v
            return space.xyzToLinear * d65
        case let .encoded(v, src):
            let lin = Vec3(src.decode(v.x), src.decode(v.y), src.decode(v.z))
            return src == space ? lin : space.xyzToLinear * (src.linearToXYZ * lin)
        }
    }

    func encoded(in space: OutputSpace) -> Vec3 {
        if case let .encoded(v, src) = self, src == space { return v }
        let l = linear(in: space).clamped(lowerBound: Vec3(repeating: 0), upperBound: Vec3(repeating: 1))
        return Vec3(space.encode(l.x), space.encode(l.y), space.encode(l.z))
    }

    /// True when the colour cannot be shown in `space` without clipping (0.2% tolerance).
    func outOfGamut(in space: OutputSpace) -> Bool {
        if case let .encoded(_, src) = self, src == space { return false }
        let l = linear(in: space)
        return l.min() < -0.002 || l.max() > 1.002
    }

    func code8(in space: OutputSpace) -> (Int, Int, Int) {
        let e = encoded(in: space)
        return (Int((e.x * 255).rounded()), Int((e.y * 255).rounded()), Int((e.z * 255).rounded()))
    }

    /// Exact CIE L*a*b* (D50) of the definition itself, without gamut clipping.
    var labD50: Vec3 {
        switch self {
        case let .xyz(v, white):
            let d50 = white == ColorMath.whiteD50 ? v : ColorMath.adaptation(from: white, to: ColorMath.whiteD50) * v
            return ColorMath.xyzToLab(d50, white: ColorMath.whiteD50)
        case let .encoded(_, space):
            let xyz = space.linearToXYZ * linear(in: space)
            return ColorMath.xyzToLab(ColorMath.adaptation(from: ColorMath.whiteD65, to: ColorMath.whiteD50) * xyz, white: ColorMath.whiteD50)
        }
    }

    func lab(in space: OutputSpace) -> Vec3 {
        ColorMath.xyzToLab(ColorMath.adaptation(from: ColorMath.whiteD65, to: ColorMath.whiteD50) * (space.linearToXYZ * linear(in: space)), white: ColorMath.whiteD50)
    }

    func color(in space: OutputSpace) -> Color {
        let shown = space.displaySpace
        let e = encoded(in: shown)
        return Color(shown == .displayP3 ? .displayP3 : .sRGB, red: e.x, green: e.y, blue: e.z, opacity: 1)
    }
}
