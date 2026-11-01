import Foundation

struct Patch: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var spec: ColorSpec
    /// Reference values as published (shown in the label overlay).
    var reference: String?
    /// Set when the patch was hand-tuned away from its default value.
    var tuned: Bool? = nil
}

/// A grid of colour patches. `physicalGap`/`physicalBorder` are fractions of one patch side and
/// describe the real card so "실물 비율" mode can mimic it (useful for Resolve Color Match overlays).
struct PatchChart: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var subtitle: String = ""
    var rows: Int
    var columns: Int
    var patches: [Patch]
    var physicalGap: Double = 0.125
    var physicalBorder: Double = 0.25
    var source: String = ""
    /// Patch width / height on the real card (1 = square).
    var patchAspect: Double = 1
    /// Free-form layout: one [x, y, w, h] per patch in card units, card is `cardSize` [w, h].
    var layoutRects: [[Double]]? = nil
    var cardSize: [Double]? = nil
    /// For a tuned custom chart: the id of the built-in chart it was tuned from (shown nested under it).
    var baseID: String? = nil

    /// The chart turned 90° clockwise (how a landscape card looks when shot in portrait).
    var rotatedClockwise: PatchChart {
        guard patches.count == rows * columns, layoutRects == nil else { return self }
        var out = self
        out.rows = columns
        out.columns = rows
        out.patchAspect = 1 / patchAspect
        out.patches = (0..<columns).flatMap { r in (0..<rows).map { c in patches[(rows - 1 - c) * columns + r] } }
        return out
    }

    var isLandscape: Bool {
        if let c = cardSize { return c[0] > c[1] }
        return Double(columns) * patchAspect > Double(rows)
    }

    func patch(row: Int, column: Int) -> Patch? {
        let i = row * columns + column
        return patches.indices.contains(i) ? patches[i] : nil
    }
}

/// JSON file layout produced from the colour-science datasets (see Resources/Charts).
struct ReferenceDataset: Decodable {
    struct Entry: Decodable { let name: String; let values: [Double] }
    let id: String
    let title: String
    let space: String          // "Lab" | "xyY" | "XYZ"
    let whitePoint: [Double]
    let rows: Int
    let columns: Int
    let source: String
    let patches: [Entry]

    func chart(subtitle: String) -> PatchChart {
        let white = SIMD2(whitePoint[0], whitePoint[1])
        let items = patches.map { e -> Patch in
            let v = Vec3(e.values[0], e.values[1], e.values[2])
            switch space {
            case "Lab":
                return Patch(name: e.name, spec: .lab(v.x, v.y, v.z, white: white),
                             reference: String(format: "L* %.2f  a* %.2f  b* %.2f", v.x, v.y, v.z))
            case "xyY":
                return Patch(name: e.name, spec: .xyz(ColorMath.xyYToXYZ(v), white: white),
                             reference: String(format: "x %.4f  y %.4f  Y %.4f", v.x, v.y, v.z))
            default:
                return Patch(name: e.name, spec: .xyz(v, white: white),
                             reference: String(format: "X %.4f  Y %.4f  Z %.4f", v.x, v.y, v.z))
            }
        }
        let fine = rows * columns > 60
        return PatchChart(id: id, title: tr(title), subtitle: subtitle, rows: rows, columns: columns, patches: items,
                          physicalGap: fine ? 0.06 : 0.125, physicalBorder: fine ? 0.15 : 0.25, source: source)
    }

    static func load(_ name: String) -> ReferenceDataset? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReferenceDataset.self, from: data)
    }
}
