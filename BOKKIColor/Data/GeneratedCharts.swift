import Foundation

/// Patch charts that are computed rather than loaded from published reference data.
enum GeneratedCharts {
    // MARK: Grayscale
    static func grayLStar(steps: Int) -> PatchChart {
        let patches = (0..<steps).map { i -> Patch in
            let l = 100 - Double(i) * 100 / Double(steps - 1)
            return Patch(name: String(format: "L* %.0f", l), spec: .lab(l, 0, 0), reference: String(format: "L* %.1f  a* 0  b* 0", l))
        }
        let cols = steps <= 11 ? steps : (steps + 1) / 2
        return PatchChart(id: "gray_l\(steps)", title: "\(steps)단 그레이 (L* 등간격)", subtitle: "지각 균일 밝기 단계",
                          rows: (steps + cols - 1) / cols, columns: cols, patches: patches, physicalGap: 0.06, physicalBorder: 0.15)
    }

    static func grayCode(id: String, title: String, subtitle: String, from: Double, to: Double, steps: Int, columns: Int) -> PatchChart {
        let patches = (0..<steps).map { i -> Patch in
            let code = from + (to - from) * Double(i) / Double(steps - 1)
            let v = (code * 255).rounded() / 255
            return Patch(name: String(format: "%.0f%%", code * 100), spec: .gray(v), reference: "code \(Int(v * 255)) / 255")
        }
        return PatchChart(id: id, title: title, subtitle: subtitle, rows: (steps + columns - 1) / columns, columns: columns,
                          patches: patches, physicalGap: 0.06, physicalBorder: 0.15)
    }

    static func field(id: String, title: String, subtitle: String, spec: ColorSpec, reference: String) -> PatchChart {
        PatchChart(id: id, title: title, subtitle: subtitle, rows: 1, columns: 1,
                   patches: [Patch(name: title, spec: spec, reference: reference)], physicalGap: 0, physicalBorder: 0)
    }

    /// 18% reflectance gray (Y = 0.18 → L* ≈ 49.5).
    static let gray18 = ColorSpec.xyz(ColorMath.xyToXYZ(ColorMath.whiteD65, Y: 0.18), white: ColorMath.whiteD65)

    /// 3-step grayscale card (white / mid gray / black bands). The card's own values are unpublished,
    /// so the official CC24 (After Nov 2014) neutral patches are used.
    static var threeStep: PatchChart {
        let items: [(String, Vec3)] = [("White 9.5", Vec3(95.19, -1.03, 2.93)), ("Neutral 5 (18%)", Vec3(50.76, -0.13, 0.14)), ("Black 2", Vec3(20.64, 0.07, -0.46))]
        return PatchChart(id: "gray3", title: "3단 그레이스케일", subtitle: "화이트 · 18% 그레이 · 블랙 띠 — 라이팅/WB 밸런스",
                          rows: 3, columns: 1,
                          patches: items.map { Patch(name: $0.0, spec: .lab($0.1.x, $0.1.y, $0.1.z), reference: String(format: "L* %.2f a* %.2f b* %.2f", $0.1.x, $0.1.y, $0.1.z)) },
                          physicalGap: 0.06, physicalBorder: 0.12, source: "CC24 After Nov 2014 중립 패치 값", patchAspect: 4.6)
    }

    // MARK: White balance
    static let cctList: [Double] = [2700, 3200, 4000, 5000, 5600, 6500, 7500]

    /// Neutral field at a CCT, scaled so the brightest channel hits `peak` in Display P3.
    static func cctSpec(_ k: Double, peak: Double = 0.9) -> ColorSpec {
        let xyz = ColorMath.xyToXYZ(ColorMath.cctToXY(k))
        let lin = OutputSpace.displayP3.xyzToLinear * xyz
        let scale = ColorMath.decodeSRGB(peak) / lin.max()
        return .xyz(xyz * scale, white: ColorMath.whiteD65)
    }

    static func cctField(_ k: Double) -> PatchChart {
        let xy = ColorMath.cctToXY(k)
        return field(id: "cct_\(Int(k))", title: "\(Int(k))K", subtitle: "AWB 중립 필드",
                     spec: cctSpec(k), reference: String(format: "CCT %.0fK  x %.4f y %.4f", k, xy.x, xy.y))
    }

    static var cctStrip: PatchChart {
        PatchChart(id: "cct_strip", title: "색온도 스트립", subtitle: "2700K–7500K 나란히", rows: 1, columns: cctList.count,
                   patches: cctList.map { cctField($0).patches[0] }, physicalGap: 0.04, physicalBorder: 0.1)
    }

    // MARK: Hue / saturation
    static func hueGrid(count: Int, l: Double = 60, c: Double = 45) -> PatchChart {
        let cols = count == 24 ? 6 : 6
        let patches = (0..<count).map { i -> Patch in
            let h = Double(i) * 360 / Double(count)
            let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
            return Patch(name: String(format: "h %.0f°", h), spec: .lab(l, a, b),
                         reference: String(format: "L* %.0f  C* %.0f  h %.1f°", l, c, h))
        }
        return PatchChart(id: "hue_\(count)", title: "색상환 \(count)분할", subtitle: "L* \(Int(l)) · C* \(Int(c)) 고정, 휴 쉬프트 확인",
                          rows: count / cols, columns: cols, patches: patches)
    }

    static var saturationSweep: PatchChart {
        let hues: [(String, Vec3)] = [("R", Vec3(1, 0, 0)), ("Y", Vec3(1, 1, 0)), ("G", Vec3(0, 1, 0)),
                                      ("C", Vec3(0, 1, 1)), ("B", Vec3(0, 0, 1)), ("M", Vec3(1, 0, 1))]
        let steps = 8
        var patches: [Patch] = []
        let mid = ColorMath.decodeSRGB(0.5)
        for (name, target) in hues {
            for s in 0..<steps {
                let t = Double(s + 1) / Double(steps)
                // Mix in linear light from 50% gray toward the full-saturation primary at the same peak.
                let lin = Vec3(repeating: mid) * (1 - t) + target * t
                let enc = Vec3(ColorMath.encodeSRGB(lin.x), ColorMath.encodeSRGB(lin.y), ColorMath.encodeSRGB(lin.z))
                patches.append(Patch(name: "\(name) \(Int(t * 100))%", spec: .encoded(enc, space: .displayP3),
                                     reference: "P3 linear mix \(Int(t * 100))%"))
            }
        }
        return PatchChart(id: "sat_sweep", title: "채도 스윕 (P3)", subtitle: "6색 × 8단, 채도 커브·클리핑 확인",
                          rows: hues.count, columns: steps, patches: patches, physicalGap: 0.06, physicalBorder: 0.15)
    }

    // MARK: Skin & memory colours
    /// Monk Skin Tone Scale (Dr. Ellis Monk / Google, CC BY 4.0, skintone.google).
    static let monkHex = ["f6ede4", "f3e7db", "f7ead0", "eadaba", "d7bd96", "a07e56", "825c43", "604134", "3a312a", "292420"]

    static var monk: PatchChart {
        PatchChart(id: "monk10", title: "Monk Skin Tone 10", subtitle: "포용적 피부톤 10단계",
                   rows: 2, columns: 5,
                   patches: monkHex.enumerated().map { Patch(name: "MST \($0.offset + 1)", spec: .hex($0.element), reference: "#\($0.element.uppercased())") },
                   source: "Monk Skin Tone Scale by Dr. Ellis Monk, Google — CC BY 4.0")
    }

    /// App-defined reference values (not a published standard) for tuning perceived "pleasing" colour.
    static let koreanSkin: [(String, Vec3)] = [
        ("밝은 피부", Vec3(72, 11, 16)), ("중간 밝은", Vec3(66, 13, 18)), ("중간", Vec3(60, 14, 19)),
        ("중간 어두운", Vec3(53, 15, 20)), ("어두운", Vec3(45, 15, 19)), ("홍조", Vec3(62, 20, 15)),
    ]

    static var skinTones: PatchChart {
        var p = koreanSkin.map { Patch(name: $0.0, spec: .lab($0.1.x, $0.1.y, $0.1.z), reference: String(format: "L* %.0f a* %.0f b* %.0f (BOKKI 참고값)", $0.1.x, $0.1.y, $0.1.z)) }
        p.insert(Patch(name: "dark skin (CC)", spec: .lab(37.54, 14.37, 14.92), reference: "L* 37.54 a* 14.37 b* 14.92"), at: 0)
        p.insert(Patch(name: "light skin (CC)", spec: .lab(64.66, 19.27, 17.50), reference: "L* 64.66 a* 19.27 b* 17.50"), at: 1)
        return PatchChart(id: "skin_kr", title: "스킨톤 (동아시아 참고)", subtitle: "CC 스킨 2 + BOKKI 참고 피부 6",
                          rows: 2, columns: 4, patches: p, source: "CC24 After Nov 2014 + BOKKI 정의 참고값")
    }

    static let memoryColors: [(String, Vec3)] = [
        ("맑은 하늘", Vec3(62, -6, -34)), ("저녁 하늘", Vec3(68, 22, 38)), ("바다", Vec3(48, -22, -26)), ("잔디", Vec3(50, -36, 42)),
        ("나뭇잎", Vec3(40, -22, 30)), ("벚꽃", Vec3(82, 16, 2)), ("바나나", Vec3(84, 2, 72)), ("오렌지", Vec3(66, 40, 70)),
        ("토마토", Vec3(46, 58, 40)), ("김치", Vec3(44, 48, 38)), ("흰 쌀밥", Vec3(92, 0, 6)), ("커피", Vec3(30, 10, 16)),
    ]

    static var memory: PatchChart {
        PatchChart(id: "memory", title: "메모리 컬러", subtitle: "사람이 기억하는 '예쁜 색' 기준",
                   rows: 3, columns: 4,
                   patches: memoryColors.map { Patch(name: $0.0, spec: .lab($0.1.x, $0.1.y, $0.1.z), reference: String(format: "L* %.0f a* %.0f b* %.0f (BOKKI 참고값)", $0.1.x, $0.1.y, $0.1.z)) },
                   source: "BOKKI 정의 참고값 (표준 아님)")
    }

    // MARK: Combos
    static func combo(cc24: PatchChart) -> PatchChart {
        var p = cc24.patches
        p += grayLStar(steps: 8).patches                     // 8 neutral steps
        p += [0, 2, 4, 6, 8].map { monk.patches[$0] }         // 5 skin
        p += koreanSkin.prefix(3).map { Patch(name: $0.0, spec: .lab($0.1.x, $0.1.y, $0.1.z)) }
        return PatchChart(id: "combo40", title: "BOKKI 콤보 40", subtitle: "24색 + 8단 그레이 + 피부 8", rows: 5, columns: 8, patches: p,
                          physicalGap: 0.1, physicalBorder: 0.2, source: cc24.source)
    }

    static func wideGamut(cc24: PatchChart) -> PatchChart {
        var p = cc24.patches
        let prim: [(String, Vec3)] = [("P3 Red", Vec3(1, 0, 0)), ("P3 Green", Vec3(0, 1, 0)), ("P3 Blue", Vec3(0, 0, 1)),
                                      ("P3 Cyan", Vec3(0, 1, 1)), ("P3 Magenta", Vec3(1, 0, 1)), ("P3 Yellow", Vec3(1, 1, 0))]
        p += prim.map { Patch(name: $0.0, spec: .encoded($0.1, space: .displayP3), reference: "Display P3 100%") }
        return PatchChart(id: "wide30", title: "와이드 개멋 30", subtitle: "24색 + P3 원색/2차색 6", rows: 5, columns: 6, patches: p, source: cc24.source)
    }

    static func cc24Plus(cc24: PatchChart) -> PatchChart {
        var p = cc24.patches
        p += grayCode(id: "", title: "", subtitle: "", from: 1, to: 0, steps: 6, columns: 6).patches
        return PatchChart(id: "cc24_gray", title: "24색 + 6단 그레이", subtitle: "명부~암부 코드값 단계 추가", rows: 5, columns: 6, patches: p, source: cc24.source)
    }

    /// The 24 manufacturer sRGB hex values listed with the original Classic chart (Wikipedia, citing X-Rite).
    static let cc24ManufacturerHex = ["735244", "c29682", "627a9d", "576c43", "8580b1", "67bdaa", "d67e2c", "505ba6", "c15a63", "5e3c6c", "9dbc40", "e0a32e",
                                      "383d96", "469449", "af363c", "e7c71f", "bb5695", "0885a1", "f3f3f2", "c8c8c8", "a0a0a0", "7a7a7a", "555555", "343434"]

    static func cc24Hex(names: [String]) -> PatchChart {
        PatchChart(id: "cc24_hex", title: "24색 클래식 (제조사 sRGB HEX)", subtitle: "#735244 … 제조사 공개 sRGB 코드값 그대로",
                   rows: 4, columns: 6,
                   patches: zip(names, cc24ManufacturerHex).map { Patch(name: $0, spec: .hex($1), reference: "sRGB #\($1.uppercased())") },
                   source: "Manufacturer sRGB values (Wikipedia 'ColorChecker', citing X-Rite)")
    }

    /// 24 patches + pure black (0) and pure white (255) as used by grading tools' chart readouts.
    static func cc26(cc24: PatchChart) -> PatchChart {
        var p = cc24.patches
        p.append(Patch(name: "Pure Black", spec: .gray(0), reference: "code 0"))
        p.append(Patch(name: "Pure White", spec: .gray(1), reference: "code 255"))
        return PatchChart(id: "cc26", title: "26색 (24색 + 퓨어 블랙/화이트)", subtitle: "디지털 0 / 255 기준점 추가", rows: 5, columns: 6,
                          patches: p, source: cc24.source)
    }

    /// Video-style card: skin column, near-white/black column, 4 gray bands, two chroma columns (BOKKI-defined values).
    static var videoStyle: PatchChart {
        func lab(_ n: String, _ l: Double, _ a: Double, _ b: Double, _ ref: String = "BOKKI 정의") -> Patch {
            Patch(name: n, spec: .lab(l, a, b), reference: String(format: "L* %.1f a* %.1f b* %.1f · ", l, a, b) + ref)
        }
        let skin = [lab("dark skin", 37.54, 14.37, 14.92, "CC24"), lab("tan", 52, 22, 32), lab("light tan", 66, 18, 28),
                    lab("light skin", 64.66, 19.27, 17.50, "CC24"), lab("fair", 78, 12, 16), lab("very fair", 85, 8, 12), lab("black", 20.64, 0.07, -0.46, "CC24")]
        let nearBW = [lab("black 2", 20.64, 0.07, -0.46, "CC24"), lab("near black", 28, 0, 0), lab("neutral 8", 81.29, -0.57, 0.44, "CC24"),
                      lab("near white", 89, 0, 0), lab("white 9.5", 95.19, -1.03, 2.93, "CC24"), lab("white 9.5", 95.19, -1.03, 2.93, "CC24")]
        let bands = [lab("white band", 95.19, -1.03, 2.93, "CC24"), lab("light gray (6.5)", 66.89, -0.75, -0.06, "CC24"),
                     lab("dark gray (3.5)", 35.63, -0.46, -0.48, "CC24"), Patch(name: "super black", spec: .gray(0), reference: "code 0")]
        let hues: [(String, Double)] = [("yellow", 95), ("red", 30), ("magenta", 340), ("blue", 285), ("cyan", 210), ("green", 140)]
        var chroma: [Patch] = [lab("black 2", 20.64, 0.07, -0.46, "CC24"), lab("white 9.5", 95.19, -1.03, 2.93, "CC24")]
        for (n, h) in hues {
            let r = h * .pi / 180
            chroma.append(lab("\(n) light", n == "yellow" ? 86 : 64, 50 * cos(r), 50 * sin(r)))
            chroma.append(lab("\(n) dark", n == "yellow" ? 62 : 42, 42 * cos(r), 42 * sin(r)))
        }
        var rects: [[Double]] = []
        for i in 0..<7 { rects.append([0.4, 0.4 + Double(i) * 1.1, 0.9, 0.9]) }
        for i in 0..<6 { rects.append([1.5, 1.5 + Double(i) * 1.1, 0.9, 0.9]) }
        for i in 0..<4 { rects.append([2.8, 0.4 + Double(i) * 1.95, 8.2, 1.75]) }
        rects.append([11.4, 0.4, 0.9, 0.9]); rects.append([12.5, 0.4, 0.9, 0.9])
        for i in 0..<6 { rects.append([11.4, 1.5 + Double(i) * 1.1, 0.9, 0.9]); rects.append([12.5, 1.5 + Double(i) * 1.1, 0.9, 0.9]) }
        return PatchChart(id: "video_style", title: "비디오형 체커", subtitle: "피부톤 열 + 그레이 띠 + 원색 열 (공식 Video 값 비공개 → BOKKI 정의)",
                          rows: 7, columns: 1, patches: skin + nearBW + bands + chroma,
                          source: "레이아웃만 비디오 차트 참고, 값은 CC24 공식 + BOKKI 정의", layoutRects: rects, cardSize: [13.8, 8.2])
    }

    /// Photographer-style 6×4: hue families in light/mid/dark + grays (BOKKI-defined values).
    static var photoStyle: PatchChart {
        func fam(_ n: String, _ h: Double, _ c: [Double], _ l: [Double]) -> [Patch] {
            ["밝은", "중간", "어두운"].enumerated().map { i, t in
                let r = h * .pi / 180
                return Patch(name: "\(n) \(t)", spec: .lab(l[i], c[i] * cos(r), c[i] * sin(r)), reference: String(format: "L* %.0f C* %.0f h %.0f° · BOKKI 정의", l[i], c[i], h))
            }
        }
        var p: [Patch] = []
        p += fam("피부", 55, [18, 26, 30], [82, 55, 30]); p += fam("보라", 305, [20, 40, 50], [86, 55, 28])
        p += fam("노랑", 95, [45, 70, 85], [95, 92, 86]); p += fam("초록", 140, [22, 48, 30], [84, 56, 30])
        p += fam("빨강", 20, [32, 55, 72], [66, 52, 45]); p += fam("파랑", 270, [25, 50, 80], [82, 55, 30])
        for l in [100.0, 90, 80, 70, 50] { p.append(Patch(name: "L* \(Int(l))", spec: .lab(l, 0, 0), reference: "L* \(Int(l)) neutral")) }
        p.append(Patch(name: "Black", spec: .gray(0), reference: "code 0"))
        return PatchChart(id: "photo_style", title: "포토 체커 6×4", subtitle: "피부·보라·노랑·초록·빨강·파랑 3단 + 그레이", rows: 4, columns: 6,
                          patches: p, physicalGap: 0.15, physicalBorder: 0.25, source: "BOKKI 정의", patchAspect: 0.85)
    }

    /// 55-swatch sheet: 11 grays, 11 earth/skin tones, 33 hues (BOKKI-defined; labels show HEX/RGB/CMYK).
    static var swatch55: PatchChart {
        var cols: [[Patch]] = []
        cols.append((0..<11).map { i in let v = 1 - Double(i) / 10; return Patch(name: "K \(i * 10)%", spec: .gray(v), reference: "code \(Int((v * 255).rounded()))") })
        cols.append((0..<11).map { i in
            let l = 88 - Double(i) * 6.5, c = 10 + Double(i % 4) * 7, h = 55 + Double(i % 3) * 10
            return Patch(name: "earth \(i + 1)", spec: .lab(l, c * cos(h * .pi / 180), c * sin(h * .pi / 180)), reference: "BOKKI 정의")
        })
        for col in 0..<3 {
            cols.append((0..<11).map { i in
                let k = col * 11 + i, h = Double(k) * 360 / 33
                let l = 50 + 15 * cos((h - 95) * .pi / 180)    // yellows lighter, blues darker
                return Patch(name: String(format: "h %.0f°", h), spec: .lab(l, 60 * cos(h * .pi / 180), 60 * sin(h * .pi / 180)), reference: "BOKKI 정의")
            })
        }
        var p: [Patch] = []
        for r in 0..<11 { for c in 0..<5 { p.append(cols[c][r]) } }
        return PatchChart(id: "swatch55", title: "스와치 시트 55", subtitle: "그레이 11 · 어스톤 11 · 색상 33 (라벨에 HEX/RGB/CMYK)", rows: 11, columns: 5,
                          patches: p, physicalGap: 0.15, physicalBorder: 0.2, source: "BOKKI 정의", patchAspect: 1.6)
    }

    static var sevenBars: PatchChart {
        let bars: [(String, Vec3)] = [("White", Vec3(1, 1, 1)), ("Yellow", Vec3(1, 1, 0)), ("Cyan", Vec3(0, 1, 1)), ("Green", Vec3(0, 1, 0)),
                                      ("Magenta", Vec3(1, 0, 1)), ("Red", Vec3(1, 0, 0)), ("Blue", Vec3(0, 0, 1))]
        return PatchChart(id: "bars7", title: "7색 컬러바 100%", subtitle: "화이트·옐로·시안·그린·마젠타·레드·블루", rows: 1, columns: 7,
                          patches: bars.map { Patch(name: $0.0, spec: .encoded($0.1, space: .sRGB), reference: "Rec.709 100%") },
                          physicalGap: 0, physicalBorder: 0.15, patchAspect: 0.22)
    }

    // MARK: Video bars (EG-1 / EBU style, sRGB approximations of the broadcast levels)
    static var ebuBars: PatchChart {
        let bars: [(String, Vec3)] = [("White 100", Vec3(1, 1, 1)), ("Yellow 75", Vec3(0.75, 0.75, 0)), ("Cyan 75", Vec3(0, 0.75, 0.75)),
                                      ("Green 75", Vec3(0, 0.75, 0)), ("Magenta 75", Vec3(0.75, 0, 0.75)), ("Red 75", Vec3(0.75, 0, 0)),
                                      ("Blue 75", Vec3(0, 0, 0.75)), ("Black", Vec3(0, 0, 0))]
        return PatchChart(id: "ebu75", title: "EBU 75% 컬러바", subtitle: "Rec.709 75% 바", rows: 1, columns: bars.count,
                          patches: bars.map { Patch(name: $0.0, spec: .encoded($0.1, space: .sRGB), reference: "Rec.709") },
                          physicalGap: 0, physicalBorder: 0)
    }

    static var fullBars: PatchChart {
        let bars: [(String, Vec3)] = [("White", Vec3(1, 1, 1)), ("Yellow", Vec3(1, 1, 0)), ("Cyan", Vec3(0, 1, 1)), ("Green", Vec3(0, 1, 0)),
                                      ("Magenta", Vec3(1, 0, 1)), ("Red", Vec3(1, 0, 0)), ("Blue", Vec3(0, 0, 1)), ("Black", Vec3(0, 0, 0))]
        return PatchChart(id: "bars100", title: "100% 컬러바", subtitle: "Rec.709 풀 레벨", rows: 1, columns: bars.count,
                          patches: bars.map { Patch(name: $0.0, spec: .encoded($0.1, space: .sRGB), reference: "Rec.709 100%") },
                          physicalGap: 0, physicalBorder: 0)
    }
}
