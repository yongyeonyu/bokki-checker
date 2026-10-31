import SwiftUI

/// Colour slate shot at the start of a D-Log clip: reference checker + neutral strip + shot metadata,
/// so the clip can be matched later (e.g. DaVinci Resolve Color Match with the Classic chart overlay).
struct SlateView: View {
    let space: OutputSpace
    let aspect: AspectMode
    var showControls: Bool
    var onSelect: (Patch?) -> Void

    @AppStorage("slate.chart") private var chartID = "cc24_after2014"
    @AppStorage("slate.project") private var project = "BOKKI"
    @AppStorage("slate.camera") private var camera = "Osmo Action"
    @AppStorage("slate.profile") private var profile = "D-Log M"
    @AppStorage("slate.wb") private var wb = "5600K"
    @AppStorage("slate.iso") private var iso = "ISO 100"
    @AppStorage("slate.scene") private var scene = "1"
    @AppStorage("slate.take") private var take = 1
    @State private var editing = false
    @Environment(CustomChartStore.self) private var store

    private var chart: PatchChart {
        ChartCatalog.references[chartID] ?? store.charts.first { $0.id == chartID } ?? ChartCatalog.cc24
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                PatchGridView(chart: chart, space: space, aspect: aspect, surround: .black, onSelect: onSelect)
                    .frame(width: wide ? geo.size.width * 0.74 : nil, height: wide ? nil : geo.size.height * 0.6)
                info(wide: wide)
            }
        }
        .background(Color.black)
        .sheet(isPresented: $editing) { editor }
    }

    private func info(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.system(.headline, design: .monospaced))
            }
            Text(project).font(.title2.bold()).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("S \(scene)").font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("T \(take)").font(.system(size: 34, weight: .heavy, design: .rounded))
            }
            Group {
                Text(camera)
                Text("\(profile) · \(wb) · \(iso)")
                Text(chart.title).foregroundStyle(.gray)
            }
            .font(.system(.subheadline, design: .monospaced))
            .lineLimit(2)
            Spacer(minLength: 4)
            neutralStrip.frame(maxHeight: wide ? 120 : 70)
            if showControls {
                HStack {
                    Button { take = max(1, take - 1) } label: { Image(systemName: "minus.circle.fill") }
                    Button { take += 1 } label: { Image(systemName: "plus.circle.fill") }
                    Spacer()
                    Button("편집") { editing = true }.buttonStyle(.borderedProminent)
                }
                .font(.title2)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// White / 18% gray / black for quick WB and exposure picking in the grade.
    private var neutralStrip: some View {
        let items: [(String, ColorSpec)] = [("W", .gray(1)), ("18%", GeneratedCharts.gray18), ("K", .gray(0))]
        return HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                Rectangle().fill(item.1.color(in: space))
                    .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 1))
                    .onTapGesture { onSelect(Patch(name: item.0, spec: item.1)) }
            }
        }
    }

    private var editor: some View {
        NavigationStack {
            Form {
                Section("기준 체커") {
                    Picker("체커", selection: $chartID) {
                        ForEach(ChartCatalog.referenceIDs.filter { !$0.hasPrefix("sg140") }, id: \.self) { id in
                            Text(ChartCatalog.references[id]?.title ?? id).tag(id)
                        }
                        ForEach(store.charts.filter { [24, 45].contains($0.patches.count) }) { c in
                            Text("✎ " + c.title).tag(c.id)
                        }
                    }
                }
                Section("촬영 정보") {
                    TextField("프로젝트", text: $project)
                    TextField("카메라", text: $camera)
                    Picker("프로파일", selection: $profile) {
                        ForEach(["D-Log M", "D-Log", "HLG", "Normal", "Log (기타)"], id: \.self) { Text($0) }
                    }
                    TextField("화이트밸런스", text: $wb)
                    TextField("ISO / 셔터", text: $iso)
                    TextField("씬", text: $scene)
                    Stepper("테이크 \(take)", value: $take, in: 1...999)
                }
                Section("Resolve 매칭 팁") {
                    Text("컬러 페이지 › Color Match › 차트: ColorChecker Classic (45색은 수동 매칭), Source Gamma: DJI D-Log M, Target: Rec.709 Gamma 2.4. 체커 화면이 프레임의 1/3 이상 차도록, 반사 없이 정면에서 촬영하세요.")
                        .font(.footnote)
                }
            }
            .navigationTitle("슬레이트 편집")
            .toolbar { Button("완료") { editing = false } }
        }
    }
}
