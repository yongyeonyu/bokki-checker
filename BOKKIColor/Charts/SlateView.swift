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
    }

    private func info(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.system(.headline, design: .monospaced))
            }
            // Every field is typed into directly: tapping the text puts the cursor there.
            slateField("프로젝트", $project, font: .title2.bold())
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                HStack(spacing: 4) {
                    Text("S").font(.system(size: 34, weight: .heavy, design: .rounded))
                    slateField("씬", $scene, font: .system(size: 34, weight: .heavy, design: .rounded))
                        .frame(width: 90)
                }
                HStack(spacing: 4) {
                    Text("T").font(.system(size: 34, weight: .heavy, design: .rounded))
                    TextField("테이크", value: $take, format: .number)
                        .keyboardType(.numberPad)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .frame(width: 90)
                }
                Button { take = max(1, take - 1) } label: { Image(systemName: "minus.circle.fill") }
                Button { take += 1 } label: { Image(systemName: "plus.circle.fill") }
            }
            .font(.title2)
            Group {
                SlatePickerField(prompt: "카메라", text: $camera, options: Self.cameras)
                HStack(spacing: 6) {
                    SlatePickerField(prompt: "프로파일", text: $profile, options: Self.profiles)
                    Text("·")
                    SlatePickerField(prompt: "WB", text: $wb, options: Self.whiteBalances)
                    Text("·")
                    SlatePickerField(prompt: "ISO", text: $iso, options: Self.isos)
                }
            }
            .font(.system(.subheadline, design: .monospaced))
            Menu {
                ForEach(ChartCatalog.referenceIDs.filter { !$0.hasPrefix("sg140") }, id: \.self) { id in
                    Button(ChartCatalog.references[id]?.title ?? id) { chartID = id }
                }
                ForEach(store.charts.filter { [24, 45].contains($0.patches.count) }) { c in
                    Button("✎ " + c.title) { chartID = c.id }
                }
            } label: {
                Label(chart.title, systemImage: "chevron.up.chevron.down")
                    .font(.system(.subheadline, design: .monospaced)).foregroundStyle(.gray)
            }
            Spacer(minLength: 4)
            neutralStrip.frame(maxHeight: wide ? 120 : 70)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static let cameras = ["Osmo Action 5 Pro", "Osmo Action 4", "Osmo Pocket 3", "Osmo 360", "iPhone", "BOKKI CAM"]
    static let profiles = ["D-Log M", "D-Log", "HLG", "Normal", "Rec.709"]
    static let whiteBalances = ["Auto", "2800K", "3200K", "4000K", "5000K", "5600K", "6500K", "7500K"]
    static let isos = ["ISO 100", "ISO 200", "ISO 400", "ISO 800", "ISO 1600", "ISO 3200"]

    /// Borderless text field styled as slate text; focus (cursor) comes from a plain tap.
    private func slateField(_ prompt: String, _ text: Binding<String>, font: Font = .system(.subheadline, design: .monospaced)) -> some View {
        TextField(prompt, text: text)
            .font(font)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .lineLimit(1)
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
}

/// Slate value with presets: tap opens a dropdown on the slate itself; "직접 입력" switches to typing.
private struct SlatePickerField: View {
    let prompt: String
    @Binding var text: String
    let options: [String]
    @State private var typing = false
    @FocusState private var focused: Bool

    var body: some View {
        if typing {
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .onSubmit { typing = false }
                .onChange(of: focused) { _, now in if !now { typing = false } }
                .onAppear { focused = true }
        } else {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button { text = option } label: {
                        if option == text { Label(option, systemImage: "checkmark") } else { Text(option) }
                    }
                }
                Divider()
                Button { typing = true } label: { Label("직접 입력", systemImage: "keyboard") }
            } label: {
                HStack(spacing: 2) {
                    Text(text.isEmpty ? prompt : text).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
                }
                .foregroundStyle(.white)
            }
        }
    }
}
