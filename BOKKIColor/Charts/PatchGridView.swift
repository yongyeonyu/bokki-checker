import SwiftUI

/// Computes patch rectangles for both aspect modes.
struct PatchLayout {
    let card: CGRect
    let rects: [CGRect]

    init(chart: PatchChart, in size: CGSize, aspect: AspectMode) {
        let cols = CGFloat(chart.columns), rows = CGFloat(chart.rows)
        let g = CGFloat(chart.physicalGap), b = CGFloat(chart.physicalBorder), pa = CGFloat(chart.patchAspect)
        var rects: [CGRect] = []
        if let custom = chart.layoutRects, let card = chart.cardSize {
            let cw = CGFloat(card[0]), ch = CGFloat(card[1])
            let sx: CGFloat, sy: CGFloat, ox: CGFloat, oy: CGFloat
            if aspect == .physical {
                let s = min(size.width / cw, size.height / ch)
                (sx, sy, ox, oy) = (s, s, (size.width - cw * s) / 2, (size.height - ch * s) / 2)
            } else {
                (sx, sy, ox, oy) = (size.width / cw, size.height / ch, 0, 0)
            }
            self.card = CGRect(x: ox, y: oy, width: cw * sx, height: ch * sy)
            self.rects = custom.map { CGRect(x: ox + $0[0] * sx, y: oy + $0[1] * sy, width: $0[2] * sx, height: $0[3] * sy) }
            return
        }
        switch aspect {
        case .physical:
            // Patches at the card's aspect, with the real card's gap/border proportions, centred.
            let unitW = cols * pa + (cols - 1) * g + 2 * b
            let unitH = rows + (rows - 1) * g + 2 * b
            let s = min(size.width / unitW, size.height / unitH)
            let card = CGRect(x: (size.width - unitW * s) / 2, y: (size.height - unitH * s) / 2, width: unitW * s, height: unitH * s)
            for r in 0..<chart.rows {
                for c in 0..<chart.columns {
                    rects.append(CGRect(x: card.minX + (b + CGFloat(c) * (pa + g)) * s,
                                        y: card.minY + (b + CGFloat(r) * (1 + g)) * s, width: s * pa, height: s))
                }
            }
            self.card = card
        case .fill:
            // Stretch patches to fill the whole screen; keep thin separators so patches stay detectable.
            let cellW = size.width / cols, cellH = size.height / rows
            let gap = g > 0 ? max(2, min(cellW, cellH) * g * 0.5) : 0
            for r in 0..<chart.rows {
                for c in 0..<chart.columns {
                    rects.append(CGRect(x: CGFloat(c) * cellW + gap / 2, y: CGFloat(r) * cellH + gap / 2,
                                        width: cellW - gap, height: cellH - gap))
                }
            }
            self.card = CGRect(origin: .zero, size: size)
        }
        self.rects = rects
    }

    func index(at p: CGPoint) -> Int? { rects.firstIndex { $0.contains(p) } }
}

struct PatchGridView: View {
    let chart: PatchChart
    let space: OutputSpace
    let aspect: AspectMode
    let surround: Surround
    var showLabels = false
    /// Called with the tapped patch, or nil when the tap missed every patch.
    var onSelect: (Patch?) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let layout = PatchLayout(chart: chart, in: geo.size, aspect: aspect)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(surround.spec.color(in: space)))
                    ctx.fill(Path(layout.card), with: .color(.black))
                    for (i, rect) in layout.rects.enumerated() where i < chart.patches.count {
                        ctx.fill(Path(rect), with: .color(chart.patches[i].spec.color(in: space)))
                    }
                }
                if showLabels {
                    ForEach(Array(chart.patches.enumerated()), id: \.offset) { i, patch in
                        if i < layout.rects.count {
                            PatchLabel(patch: patch, space: space, compact: layout.rects[i].width < 90)
                                .frame(width: layout.rects[i].width, height: layout.rects[i].height)
                                .offset(x: layout.rects[i].minX, y: layout.rects[i].minY)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { e in
                if let i = layout.index(at: e.location), i < chart.patches.count { onSelect(chart.patches[i]) } else { onSelect(nil) }
            })
        }
        .accessibilityIgnoresInvertColors()
    }
}

/// Small text label drawn on a patch, with contrasting colour chosen from luminance.
struct PatchLabel: View {
    let patch: Patch
    let space: OutputSpace
    let compact: Bool

    var body: some View {
        let info = ColorInfo(patch.spec, space: space)
        let dark = patch.spec.linear(in: space).y > 0.25
        VStack(spacing: 1) {
            Text((patch.tuned == true ? "✎ " : "") + patch.name).fontWeight(.semibold).lineLimit(1)
            if !compact { Text(info.shortLabel).multilineTextAlignment(.center) }
            if info.outOfGamut { Text("⚠︎ 개멋 밖") }
        }
        .font(.system(size: compact ? 8 : 10, design: .monospaced))
        .minimumScaleFactor(0.5)
        .foregroundStyle(dark ? Color.black : Color.white)
        .padding(2)
        .allowsHitTesting(false)
    }
}
