import Foundation

/// Code values of one patch at every common bit depth, in the chosen output space.
struct ColorInfo {
    let space: OutputSpace
    let encoded: Vec3        // 0...1 gamma-encoded
    let linear: Vec3         // unclipped linear light
    let outOfGamut: Bool

    init(_ spec: ColorSpec, space: OutputSpace) {
        self.space = space
        encoded = spec.encoded(in: space)
        linear = spec.linear(in: space)
        outOfGamut = spec.outOfGamut(in: space)
    }

    private func q(_ bits: Int) -> (Int, Int, Int) {
        let m = Double((1 << bits) - 1)
        return (Int((encoded.x * m).rounded()), Int((encoded.y * m).rounded()), Int((encoded.z * m).rounded()))
    }

    /// 24-bit true colour (8 bits per channel).
    var rgb8: (Int, Int, Int) { q(8) }
    var hex24: String { let c = rgb8; return String(format: "#%02X%02X%02X", c.0, c.1, c.2) }
    /// 10 bits per channel (video / D-Log workflows).
    var rgb10: (Int, Int, Int) { q(10) }
    /// 16 bits per channel (48-bit, e.g. 16-bit TIFF / PSD).
    var rgb16: (Int, Int, Int) { q(16) }
    /// 16-bit high colour, RGB 5-6-5.
    var rgb565: UInt16 {
        let r = UInt16((encoded.x * 31).rounded()), g = UInt16((encoded.y * 63).rounded()), b = UInt16((encoded.z * 31).rounded())
        return r << 11 | g << 5 | b
    }
    /// 8-bit colour, RGB 3-3-2 (256 colours).
    var rgb332: UInt8 {
        let r = UInt8((encoded.x * 7).rounded()), g = UInt8((encoded.y * 7).rounded()), b = UInt8((encoded.z * 3).rounded())
        return r << 5 | g << 2 | b
    }

    /// Naive CMYK from encoded RGB (no ICC profile — for reference only, not print-accurate).
    var cmyk: (Int, Int, Int, Int) {
        let k = 1 - encoded.max()
        guard k < 1 else { return (0, 0, 0, 100) }
        func ch(_ v: Double) -> Int { Int(((1 - v - k) / (1 - k) * 100).rounded()) }
        return (ch(encoded.x), ch(encoded.y), ch(encoded.z), Int((k * 100).rounded()))
    }

    /// Video legal range (8-bit 16–235, 10-bit 64–940) of the encoded value.
    private func legal(_ bits: Int) -> (Int, Int, Int) {
        let (lo, span) = bits == 8 ? (16.0, 219.0) : (64.0, 876.0)
        return (Int((lo + span * encoded.x).rounded()), Int((lo + span * encoded.y).rounded()), Int((lo + span * encoded.z).rounded()))
    }

    var lines: [(String, String)] {
        let c8 = rgb8, c10 = rgb10, c16 = rgb16
        var video: [(String, String)] = []
        if space == .rec709 {
            let l8 = legal(8), l10 = legal(10)
            video = [(tr("리미티드 8비트 (16–235)"), "R \(l8.0)  G \(l8.1)  B \(l8.2)"),
                     (tr("리미티드 10비트 (64–940)"), "R \(l10.0)  G \(l10.1)  B \(l10.2)")]
        }
        return video + [
            (tr("24비트 (8bit/ch)"), "\(hex24)   R \(c8.0)  G \(c8.1)  B \(c8.2)"),
            (tr("16비트/ch (48bit)"), "R \(c16.0)  G \(c16.1)  B \(c16.2)"),
            (tr("16비트 RGB565"), String(format: "0x%04X", rgb565)),
            (tr("8비트 RGB332"), String(format: "0x%02X  (%d)", rgb332, rgb332)),
            (tr("10비트/ch"), "R \(c10.0)  G \(c10.1)  B \(c10.2)"),
            (tr("정규화 0–1"), String(format: "%.4f  %.4f  %.4f", encoded.x, encoded.y, encoded.z)),
            (tr("CMYK (단순 변환)"), { let c = cmyk; return "C \(c.0) M \(c.1) Y \(c.2) K \(c.3)" }()),
            (tr("선형 광량"), String(format: "%.4f  %.4f  %.4f", linear.x, linear.y, linear.z)),
        ]
    }

    var shortLabel: String { let c = rgb8; return "\(hex24)\n\(c.0) \(c.1) \(c.2)" }

    var copyText: String {
        ([String(format: tr("색공간: %@"), space.title) + (outOfGamut ? tr(" (개멋 밖, 클립됨)") : "")] + lines.map { "\($0.0): \($0.1)" }).joined(separator: "\n")
    }
}
