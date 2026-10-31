import Foundation

enum PatternKind: String, Hashable, Codable {
    case grayRamp, rgbRamps, steppedRamp32, hueWheel, smpteBars, siemensStar, slantedEdge, linePairs, checkerboard, distortionGrid
}

enum ChartKind: Hashable {
    case patches(PatchChart)
    case pattern(PatternKind)
    case slate
}

struct ChartItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let kind: ChartKind

    init(_ chart: PatchChart) {
        id = chart.id; title = chart.title; subtitle = chart.subtitle; kind = .patches(chart)
    }

    init(id: String, title: String, subtitle: String, kind: ChartKind) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.kind = kind
    }
}

struct ChartCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    var items: [ChartItem]
}

enum ChartCatalog {
    static let referenceIDs = ["cc24_after2014", "cc24_before2014", "cc24_2005", "cc24_babel", "cc24_1976", "sg140_after2014", "sg140_before2014", "te226_v2"]

    static let references: [String: PatchChart] = {
        let subtitles = [
            "cc24_after2014": "X-Rite 공식 · 2014년 11월 이후 제작 차트 (기본)",
            "cc24_before2014": "X-Rite 공식 · 2014년 11월 이전 제작 차트",
            "cc24_2005": "GretagMacbeth 2005 레퍼런스",
            "cc24_babel": "BabelColor · 실물 30장 측정 평균",
            "cc24_1976": "McCamy 1976 원본 (광원 C)",
            "sg140_after2014": "X-Rite 공식 · 140패치 SG (2014.11 이후)",
            "sg140_before2014": "X-Rite 공식 · 140패치 SG (2014.11 이전)",
            "te226_v2": "Image Engineering TE226 V2 · 36색 + 9단 그레이 (YE0222 등 45색 차트 동일 배치)",
        ]
        var out: [String: PatchChart] = [:]
        for id in referenceIDs {
            if let ds = ReferenceDataset.load(id) { out[id] = ds.chart(subtitle: subtitles[id] ?? "") }
        }
        return out
    }()

    /// Default 24-patch reference used by the slate and combo charts.
    static var cc24: PatchChart { references["cc24_after2014"]! }

    static func categories(custom: [PatchChart]) -> [ChartCategory] {
        let g = GeneratedCharts.self
        var cats: [ChartCategory] = [
            ChartCategory(id: "slate", title: "촬영 슬레이트", symbol: "film", summary: "D-Log 촬영 전 먼저 찍는 컬러 매칭 슬레이트",
                          items: [ChartItem(id: "slate", title: "D-Log 컬러 슬레이트", subtitle: "24색 + 그레이 + 촬영 정보 · Resolve Color Match용", kind: .slate)]),
            ChartCategory(id: "reference", title: "레퍼런스 컬러체커", symbol: "square.grid.3x3.fill", summary: "공식 데이터 기반 24 / 140 / 45 패치",
                          items: referenceIDs.compactMap { references[$0] }.map(ChartItem.init)
                              + [ChartItem(g.cc24Hex(names: cc24.patches.map(\.name))), ChartItem(g.cc26(cc24: cc24))]),
            ChartCategory(id: "combo", title: "조합형 체커", symbol: "square.grid.4x3.fill", summary: "튜닝 목적별로 묶은 BOKKI 체커",
                          items: [ChartItem(g.videoStyle), ChartItem(g.photoStyle), ChartItem(g.combo(cc24: cc24)), ChartItem(g.cc24Plus(cc24: cc24)),
                                  ChartItem(g.wideGamut(cc24: cc24)), ChartItem(g.swatch55)]),
            ChartCategory(id: "gray", title: "그레이스케일", symbol: "circle.lefthalf.filled", summary: "톤 커브 · 감마 · 암부/명부 디테일",
                          items: [
                              ChartItem(g.threeStep),
                              ChartItem(g.grayCode(id: "gray6", title: "6단 그레이", subtitle: "100→0% 코드값", from: 1, to: 0, steps: 6, columns: 6)),
                              ChartItem(g.grayLStar(steps: 11)),
                              ChartItem(g.grayLStar(steps: 21)),
                              ChartItem(g.grayCode(id: "gray32", title: "32단 코드값 그레이", subtitle: "0~255 균등 32단", from: 0, to: 1, steps: 32, columns: 8)),
                              ChartItem(g.grayCode(id: "near_black", title: "암부 디테일 0–10%", subtitle: "블랙 크러시 확인", from: 0, to: 0.1, steps: 11, columns: 11)),
                              ChartItem(g.grayCode(id: "near_white", title: "명부 디테일 90–100%", subtitle: "하이라이트 클리핑 확인", from: 0.9, to: 1, steps: 11, columns: 11)),
                              ChartItem(id: "ramp_gray", title: "스무스 그레이 램프", subtitle: "16비트 렌더 · 밴딩 확인", kind: .pattern(.grayRamp)),
                              ChartItem(id: "ramp_rgb", title: "RGB + 그레이 램프", subtitle: "채널별 톤 커브", kind: .pattern(.rgbRamps)),
                              ChartItem(id: "ramp_step32", title: "계단 램프 32", subtitle: "코드값 8단위 계단", kind: .pattern(.steppedRamp32)),
                              ChartItem(g.field(id: "field18", title: "18% 그레이 필드", subtitle: "노출·WB 기준 (L* ≈ 49.5)", spec: g.gray18, reference: "Y 0.18")),
                              ChartItem(g.field(id: "field_white", title: "화이트 필드", subtitle: "렌즈 셰이딩 · 균일도", spec: .gray(1), reference: "code 255")),
                              ChartItem(g.field(id: "field_black", title: "블랙 필드", subtitle: "블랙 레벨 · 플레어", spec: .gray(0), reference: "code 0")),
                          ]),
            ChartCategory(id: "wb", title: "화이트밸런스", symbol: "thermometer.sun", summary: "색온도별 중립 필드로 AWB 반응 확인",
                          items: [ChartItem(g.cctStrip)] + g.cctList.map { ChartItem(g.cctField($0)) }),
            ChartCategory(id: "skin", title: "스킨톤", symbol: "person.crop.circle", summary: "인물·셀피 피부색 튜닝",
                          items: [ChartItem(g.skinTones), ChartItem(g.monk)]),
            ChartCategory(id: "hue", title: "색상 · 채도", symbol: "paintpalette", summary: "휴 쉬프트 · 채도 커브 · 메모리 컬러",
                          items: [ChartItem(g.hueGrid(count: 24)), ChartItem(g.hueGrid(count: 36)), ChartItem(g.saturationSweep),
                                  ChartItem(id: "hue_wheel", title: "연속 색상환", subtitle: "P3 원형 그라데이션", kind: .pattern(.hueWheel)),
                                  ChartItem(g.memory)]),
            ChartCategory(id: "video", title: "비디오 표준", symbol: "tv", summary: "컬러바 · 모니터 기준 신호",
                          items: [ChartItem(id: "smpte", title: "SMPTE 컬러바", subtitle: "EG-1 스타일 + PLUGE", kind: .pattern(.smpteBars)),
                                  ChartItem(g.sevenBars), ChartItem(g.ebuBars), ChartItem(g.fullBars)]),
            ChartCategory(id: "optics", title: "선명도 · 광학", symbol: "scope", summary: "포커스 · 해상력 · 왜곡 · 모아레",
                          items: [ChartItem(id: "star", title: "시먼스 스타", subtitle: "포커스 · 해상력", kind: .pattern(.siemensStar)),
                                  ChartItem(id: "edge", title: "슬랜티드 엣지 5°", subtitle: "e-SFR / MTF 측정용", kind: .pattern(.slantedEdge)),
                                  ChartItem(id: "lp", title: "라인 페어", subtitle: "1·2·3·4 px 선 · 모아레", kind: .pattern(.linePairs)),
                                  ChartItem(id: "checker", title: "체커보드", subtitle: "샤프닝 할로 · 정렬", kind: .pattern(.checkerboard)),
                                  ChartItem(id: "grid", title: "왜곡 그리드", subtitle: "배럴/핀쿠션 왜곡", kind: .pattern(.distortionGrid))]),
        ]
        cats.append(ChartCategory(id: "custom", title: "커스텀 체커", symbol: "square.and.arrow.down", summary: "가져온 체커 · 튜닝한 체커는 각 원본 체커 아래에 표시됩니다 · ⋯ 메뉴로 편집/이름 변경/삭제",
                                  items: custom.map(ChartItem.init)))
        return cats
    }
}
