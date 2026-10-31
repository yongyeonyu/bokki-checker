import Foundation

/// 3-vector / 3x3 matrix helpers kept dependency-free so the math is easy to unit test.
typealias Vec3 = SIMD3<Double>

struct Mat3 {
    var r0: Vec3, r1: Vec3, r2: Vec3

    static func * (m: Mat3, v: Vec3) -> Vec3 {
        Vec3((m.r0 * v).sum(), (m.r1 * v).sum(), (m.r2 * v).sum())
    }

    static func * (a: Mat3, b: Mat3) -> Mat3 {
        let c0 = Vec3(b.r0.x, b.r1.x, b.r2.x)
        let c1 = Vec3(b.r0.y, b.r1.y, b.r2.y)
        let c2 = Vec3(b.r0.z, b.r1.z, b.r2.z)
        func row(_ r: Vec3) -> Vec3 { Vec3((r * c0).sum(), (r * c1).sum(), (r * c2).sum()) }
        return Mat3(r0: row(a.r0), r1: row(a.r1), r2: row(a.r2))
    }

    static func diag(_ v: Vec3) -> Mat3 {
        Mat3(r0: Vec3(v.x, 0, 0), r1: Vec3(0, v.y, 0), r2: Vec3(0, 0, v.z))
    }

    var inverse: Mat3 {
        let a = r0, b = r1, c = r2
        let det = a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x) + a.z * (b.x * c.y - b.y * c.x)
        let inv = 1 / det
        return Mat3(
            r0: Vec3(b.y * c.z - b.z * c.y, a.z * c.y - a.y * c.z, a.y * b.z - a.z * b.y) * inv,
            r1: Vec3(b.z * c.x - b.x * c.z, a.x * c.z - a.z * c.x, a.z * b.x - a.x * b.z) * inv,
            r2: Vec3(b.x * c.y - b.y * c.x, a.y * c.x - a.x * c.y, a.x * b.y - a.y * b.x) * inv
        )
    }
}

enum ColorMath {
    // MARK: White points (CIE 1931 2°)
    static let whiteD50 = SIMD2<Double>(0.3457, 0.3585)   // ICC D50
    static let whiteD65 = SIMD2<Double>(0.3127, 0.3290)
    static let whiteC = SIMD2<Double>(0.31006, 0.31616)

    static func xyToXYZ(_ xy: SIMD2<Double>, Y: Double = 1) -> Vec3 {
        Vec3(xy.x * Y / xy.y, Y, (1 - xy.x - xy.y) * Y / xy.y)
    }

    static func xyYToXYZ(_ v: Vec3) -> Vec3 {
        v.y == 0 ? Vec3(0, 0, 0) : xyToXYZ(SIMD2(v.x, v.y), Y: v.z)
    }

    /// CIE L*a*b* -> XYZ relative to `white` (Y = 1 at L* = 100).
    static func labToXYZ(_ lab: Vec3, white: SIMD2<Double>) -> Vec3 {
        let w = xyToXYZ(white)
        let fy = (lab.x + 16) / 116
        let fx = fy + lab.y / 500
        let fz = fy - lab.z / 200
        let e = 216.0 / 24389.0, k = 24389.0 / 27.0
        func finv(_ t: Double) -> Double { t * t * t > e ? t * t * t : (116 * t - 16) / k }
        let yr = lab.x > k * e ? fy * fy * fy : lab.x / k
        return Vec3(finv(fx) * w.x, yr * w.y, finv(fz) * w.z)
    }

    static func xyzToLab(_ xyz: Vec3, white: SIMD2<Double>) -> Vec3 {
        let w = xyToXYZ(white)
        let e = 216.0 / 24389.0, k = 24389.0 / 27.0
        func f(_ t: Double) -> Double { t > e ? cbrt(t) : (k * t + 16) / 116 }
        let fx = f(xyz.x / w.x), fy = f(xyz.y / w.y), fz = f(xyz.z / w.z)
        return Vec3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    // MARK: Chromatic adaptation (Bradford)
    static let bradford = Mat3(
        r0: Vec3(0.8951, 0.2664, -0.1614),
        r1: Vec3(-0.7502, 1.7135, 0.0367),
        r2: Vec3(0.0389, -0.0685, 1.0296)
    )

    static func adaptation(from src: SIMD2<Double>, to dst: SIMD2<Double>) -> Mat3 {
        let s = bradford * xyToXYZ(src)
        let d = bradford * xyToXYZ(dst)
        return bradford.inverse * Mat3.diag(d / s) * bradford
    }

    // MARK: RGB spaces
    /// Normalized primary matrix (linear RGB -> XYZ) from primaries and white.
    static func rgbToXYZ(r: SIMD2<Double>, g: SIMD2<Double>, b: SIMD2<Double>, white: SIMD2<Double>) -> Mat3 {
        let pr = xyToXYZ(r), pg = xyToXYZ(g), pb = xyToXYZ(b)
        let p = Mat3(r0: Vec3(pr.x, pg.x, pb.x), r1: Vec3(pr.y, pg.y, pb.y), r2: Vec3(pr.z, pg.z, pb.z))
        let s = p.inverse * xyToXYZ(white)
        return p * Mat3.diag(s)
    }

    /// sRGB / Display P3 share this transfer function.
    static func encodeSRGB(_ v: Double) -> Double {
        let c = max(0, min(1, v))
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    static func decodeSRGB(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    // MARK: Correlated colour temperature -> chromaticity
    /// CIE daylight locus (4000–25000 K) and Kim et al. Planckian approximation (1667–4000 K).
    static func cctToXY(_ t: Double) -> SIMD2<Double> {
        if t >= 4000 {
            let x: Double
            if t <= 7000 {
                x = -4.6070e9 / pow(t, 3) + 2.9678e6 / pow(t, 2) + 0.09911e3 / t + 0.244063
            } else {
                x = -2.0064e9 / pow(t, 3) + 1.9018e6 / pow(t, 2) + 0.24748e3 / t + 0.237040
            }
            return SIMD2(x, -3.000 * x * x + 2.870 * x - 0.275)
        }
        let x = -0.2661239e9 / pow(t, 3) - 0.2343589e6 / pow(t, 2) + 0.8776956e3 / t + 0.179910
        let y: Double
        if t <= 2222 {
            y = -1.1063814 * pow(x, 3) - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
        } else {
            y = -0.9549476 * pow(x, 3) - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
        }
        return SIMD2(x, y)
    }
}
