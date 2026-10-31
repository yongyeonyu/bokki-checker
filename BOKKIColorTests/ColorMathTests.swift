import XCTest
@testable import BOKKIColor

final class ColorMathTests: XCTestCase {
    private func assertCode(_ spec: ColorSpec, _ space: OutputSpace, _ expected: (Int, Int, Int), tol: Int = 2, _ name: String, line: UInt = #line) {
        let c = spec.code8(in: space)
        XCTAssertLessThanOrEqual(abs(c.0 - expected.0), tol, "\(name) R \(c)", line: line)
        XCTAssertLessThanOrEqual(abs(c.1 - expected.1), tol, "\(name) G \(c)", line: line)
        XCTAssertLessThanOrEqual(abs(c.2 - expected.2), tol, "\(name) B \(c)", line: line)
    }

    /// Expected codes from an independent implementation using Lindbloom's published Bradford D50→D65 and sRGB matrices.
    func testCC24SRGBMatchesIndependentConversion() throws {
        let cases: [(String, [(Int, Int, Int)])] = [
            ("cc24_after2014", [(116, 79, 65), (197, 144, 127), (91, 120, 155), (91, 108, 64), (131, 127, 175), (95, 189, 172)]),
            ("cc24_before2014", [(116, 81, 67), (199, 147, 129), (91, 122, 156), (90, 108, 64), (130, 128, 176), (92, 190, 172)]),
        ]
        for (id, expected) in cases {
            let chart = try XCTUnwrap(ChartCatalog.references[id])
            for (i, e) in expected.enumerated() {
                assertCode(chart.patches[i].spec, .sRGB, e, tol: 1, "\(id) \(chart.patches[i].name)")
            }
        }
    }

    func testManufacturerHexIsExact() {
        let chart = GeneratedCharts.cc24Hex(names: Array(repeating: "x", count: 24))
        XCTAssertEqual(ColorInfo(chart.patches[0].spec, space: .sRGB).hex24, "#735244")
        XCTAssertEqual(ColorInfo(chart.patches[17].spec, space: .sRGB).hex24, "#0885A1")
    }

    func testNeutralsStayNeutral() throws {
        let chart = try XCTUnwrap(ChartCatalog.references["cc24_after2014"])
        // White 9.5 is officially slightly warm (b* +2.93), so check the darker neutrals only.
        for p in chart.patches[19...] {
            for space in OutputSpace.allCases {
                let c = p.spec.code8(in: space)
                XCTAssertLessThanOrEqual(max(c.0, c.1, c.2) - min(c.0, c.1, c.2), 3, "\(p.name) \(space) \(c)")
            }
        }
    }

    func testLabRoundTrip() {
        let lab = Vec3(50.57, 48.64, 16.67)
        let back = ColorMath.xyzToLab(ColorMath.labToXYZ(lab, white: ColorMath.whiteD50), white: ColorMath.whiteD50)
        XCTAssertEqual(back.x, lab.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, lab.y, accuracy: 1e-9)
        XCTAssertEqual(back.z, lab.z, accuracy: 1e-9)
    }

    func testWhiteMapsToFullCode() {
        let white = ColorSpec.xyz(ColorMath.xyToXYZ(ColorMath.whiteD50), white: ColorMath.whiteD50)
        for space in OutputSpace.allCases {
            let c = white.code8(in: space)
            XCTAssertEqual(c.0, 255); XCTAssertEqual(c.1, 255); XCTAssertEqual(c.2, 255)
        }
    }

    func testCyanOutOfSRGBButInsideP3() throws {
        let cyan = try XCTUnwrap(ChartCatalog.references["cc24_after2014"]).patches[17]
        XCTAssertTrue(cyan.spec.outOfGamut(in: .sRGB))
        XCTAssertFalse(cyan.spec.outOfGamut(in: .displayP3))
    }

    func testGray18() {
        let c = GeneratedCharts.gray18.code8(in: .sRGB)
        XCTAssertEqual(c.0, 118, accuracy: 1)
        XCTAssertEqual(c.0, c.1); XCTAssertEqual(c.1, c.2)
    }

    func testCCTChromaticity() {
        let d65 = ColorMath.cctToXY(6504)
        XCTAssertEqual(d65.x, 0.3127, accuracy: 0.0005)
        XCTAssertEqual(d65.y, 0.3290, accuracy: 0.0005)
        let a = ColorMath.cctToXY(2856)   // Illuminant A
        XCTAssertEqual(a.x, 0.4476, accuracy: 0.002)
        XCTAssertEqual(a.y, 0.4074, accuracy: 0.002)
    }

    func testBitDepths() {
        let info = ColorInfo(.encoded(Vec3(1, 0.5, 0), space: .sRGB), space: .sRGB)
        XCTAssertEqual(info.hex24, "#FF8000")
        XCTAssertEqual(info.rgb16.0, 65535)
        XCTAssertEqual(info.rgb16.1, 32768)
        XCTAssertEqual(info.rgb565, UInt16(31) << 11 | UInt16(32) << 5)
        XCTAssertEqual(info.rgb332, UInt8(7) << 5 | UInt8(4) << 2)
        XCTAssertEqual(info.rgb10.1, 512)
    }
}

final class Rec709Tests: XCTestCase {
    func testOETFReferencePoints() {
        XCTAssertEqual(ColorMath.encodeRec709(0.18), 0.4090, accuracy: 0.0005)   // 18% gray
        XCTAssertEqual(ColorMath.encodeRec709(1), 1, accuracy: 1e-9)
        XCTAssertEqual(ColorMath.decodeRec709(ColorMath.encodeRec709(0.42)), 0.42, accuracy: 1e-9)
        XCTAssertEqual(ColorMath.decodeRec709(ColorMath.encodeRec709(0.01)), 0.01, accuracy: 1e-9)
    }

    func testSameLightAsSRGB() throws {
        // Rec.709 shares sRGB primaries, so the emitted light must match; only the code values differ.
        let spec = try XCTUnwrap(ChartCatalog.references["cc24_after2014"]).patches[1].spec
        let a = spec.linear(in: .sRGB), b = spec.linear(in: .rec709)
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9); XCTAssertEqual(a.y, b.y, accuracy: 1e-9); XCTAssertEqual(a.z, b.z, accuracy: 1e-9)
        XCTAssertNotEqual(spec.code8(in: .sRGB).0, spec.code8(in: .rec709).0)
    }

    func testLegalRangeAndBars() {
        let white = ColorInfo(.gray(1), space: .rec709)
        XCTAssertTrue(white.lines.contains { $0.1 == "R 235  G 235  B 235" })
        XCTAssertTrue(white.lines.contains { $0.1 == "R 940  G 940  B 940" })
        // A 75% bar is a 709 signal of 0.75: full 191, legal 180.
        let bar = ColorInfo(.encoded(Vec3(0.75, 0.75, 0), space: .rec709), space: .rec709)
        XCTAssertEqual(bar.rgb8.0, 191)
        XCTAssertTrue(bar.lines.contains { $0.1.hasPrefix("R 180  G 180  B 16") })
    }
}

final class TuningTests: XCTestCase {
    func testLabD50IsExactForLabDefinitions() {
        let lab = ColorSpec.lab(42.43, 51.05, 28.62).labD50
        XCTAssertEqual(lab.x, 42.43, accuracy: 1e-9)
        XCTAssertEqual(lab.y, 51.05, accuracy: 1e-9)
        XCTAssertEqual(lab.z, 28.62, accuracy: 1e-9)
    }

    func testTunedChartDiffersAndResetRestores() throws {
        let base = try XCTUnwrap(ChartCatalog.references["cc24_after2014"])
        var working = base
        working.patches[0].spec = .lab(38.0, 14.37, 14.92)
        working.patches[0].tuned = true
        XCTAssertNotEqual(working, base)
        working.patches[0] = base.patches[0]
        XCTAssertEqual(working, base)
    }

    func testBaseIDSurvivesJSON() throws {
        var chart = try XCTUnwrap(ChartCatalog.references["cc24_after2014"])
        chart.id = "custom_test"
        chart.baseID = "cc24_after2014"
        let decoded = try JSONDecoder().decode(PatchChart.self, from: JSONEncoder().encode(chart))
        XCTAssertEqual(decoded.baseID, "cc24_after2014")
    }

    func testTunedChartRoundTripsThroughJSON() throws {
        var chart = try XCTUnwrap(ChartCatalog.references["cc24_after2014"])
        chart.patches[3].spec = .encoded(Vec3(0.3, 0.4, 0.2), space: .displayP3)
        chart.patches[3].tuned = true
        let decoded = try JSONDecoder().decode(PatchChart.self, from: JSONEncoder().encode(chart))
        XCTAssertEqual(decoded, chart)
    }
}

final class DatasetTests: XCTestCase {
    func testAllReferenceDatasetsLoad() {
        let counts = ["cc24_after2014": 24, "cc24_before2014": 24, "cc24_2005": 24, "cc24_babel": 24, "cc24_1976": 24,
                      "sg140_after2014": 140, "sg140_before2014": 140, "te226_v2": 45]
        for (id, n) in counts {
            let chart = ChartCatalog.references[id]
            XCTAssertNotNil(chart, id)
            XCTAssertEqual(chart?.patches.count, n, id)
            XCTAssertEqual((chart?.rows ?? 0) * (chart?.columns ?? 0), n, id)
        }
    }

    func testSGLayoutLettersAreColumns() throws {
        let sg = try XCTUnwrap(ChartCatalog.references["sg140_after2014"])
        XCTAssertEqual(sg.patch(row: 0, column: 0)?.name, "A1")
        XCTAssertEqual(sg.patch(row: 0, column: 13)?.name, "N1")
        XCTAssertEqual(sg.patch(row: 9, column: 0)?.name, "A10")
    }

    func testRotationMatchesPortraitPhoto() throws {
        // Rotated SG: rows A…N top to bottom, columns 10…1 left to right.
        let r = try XCTUnwrap(ChartCatalog.references["sg140_after2014"]).rotatedClockwise
        XCTAssertEqual(r.rows, 14); XCTAssertEqual(r.columns, 10)
        XCTAssertEqual(r.patch(row: 0, column: 0)?.name, "A10")
        XCTAssertEqual(r.patch(row: 0, column: 9)?.name, "A1")
        XCTAssertEqual(r.patch(row: 13, column: 9)?.name, "N1")
    }

    func testAllCategoriesBuild() {
        let cats = ChartCatalog.categories(custom: [])
        XCTAssertGreaterThan(cats.flatMap(\.items).count, 40)
    }

    func testCSVImport() throws {
        let csv = "LAB\n#columns=2\ndark skin,37.54,14.37,14.92\nwhite,95.19,-1.03,2.93\nblack,20.64,0.07,-0.46\n"
        let chart = try XCTUnwrap(CustomChartStore.parse(csv, title: "t"))
        XCTAssertEqual(chart.patches.count, 3)
        XCTAssertEqual(chart.columns, 2)
        XCTAssertEqual(chart.rows, 2)
    }

    func testCGATSImport() throws {
        let cgats = """
        CGATS.17
        NUMBER_OF_FIELDS 4
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        NUMBER_OF_SETS 2
        BEGIN_DATA
        1 37.54 14.37 14.92
        2 64.66 19.27 17.50
        END_DATA
        """
        let chart = try XCTUnwrap(CustomChartStore.parse(cgats, title: "c"))
        XCTAssertEqual(chart.patches.count, 2)
    }
}
