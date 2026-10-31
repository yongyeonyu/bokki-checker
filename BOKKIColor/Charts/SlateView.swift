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
    @AppStorage("slate.sceneNo") private var scene = 1
    @AppStorage("slate.take") private var take = 1
    /// Only the title and camera name are typed; everything else is picked or stepped.
    enum Field { case title, camera }
    @FocusState private var focus: Field?
    @Environment(CustomChartStore.self) private var store

    private var chart: PatchChart {
        ChartCatalog.references[chartID] ?? store.charts.first { $0.id == chartID } ?? ChartCatalog.cc24
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            // While typing, the checker shrinks so the field being edited stays above the keyboard.
            let chartShare = focus == nil ? (wide ? 0.62 : 0.6) : (wide ? 0.4 : 0.25)
            layout {
                PatchGridView(chart: chart, space: space, aspect: aspect, surround: .black, onSelect: onSelect)
                    .frame(width: wide ? geo.size.width * chartShare : nil, height: wide ? nil : geo.size.height * chartShare)
                info(wide: wide)
            }
            .animation(.easeInOut(duration: 0.2), value: focus)
        }
        .background(Color.black.ignoresSafeArea())
        // Close-keyboard button, pinned just above the keyboard while typing.
        .overlay(alignment: .bottomTrailing) {
            if focus != nil {
                Button { focus = nil } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 40)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel("키보드 닫기")
                .padding(10)
                .transition(.opacity)
            }
        }
    }

    private func info(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Self.stamp.string(from: ctx.date))
                    .font(.system(.headline, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            // Tapping the title or camera name puts the cursor there directly.
            slateField("영상 제목", $project, font: (wide ? Font.title3 : .title2).bold())
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onSubmit { focus = .camera }
            // Side by side when there is room, stacked in the narrow landscape column.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) {
                    counter("S", value: $scene, size: wide ? 28 : 34)
                    counter("T", value: $take, size: wide ? 28 : 34)
                }
                VStack(alignment: .leading, spacing: 4) {
                    counter("S", value: $scene, size: 28)
                    counter("T", value: $take, size: 28)
                }
            }
            Group {
                HStack(spacing: 4) {
                    slateField("카메라 이름", $camera)
                        .focused($focus, equals: .camera)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                    Menu {
                        ForEach(Self.cameras, id: \.self) { name in Button(name) { camera = name } }
                    } label: {
                        Image(systemName: "chevron.down").font(.caption2).opacity(0.6).frame(width: 28, height: 28)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        SlatePickerField(prompt: "프로파일", text: $profile, options: Self.profiles)
                        Text("·")
                        SlatePickerField(prompt: "WB", text: $wb, options: Self.whiteBalances)
                        Text("·")
                        SlatePickerField(prompt: "ISO", text: $iso, options: Self.isos)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SlatePickerField(prompt: "프로파일", text: $profile, options: Self.profiles)
                        HStack(spacing: 6) {
                            SlatePickerField(prompt: "WB", text: $wb, options: Self.whiteBalances)
                            Text("·")
                            SlatePickerField(prompt: "ISO", text: $iso, options: Self.isos)
                        }
                    }
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
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4)
            neutralStrip.frame(maxHeight: wide ? 120 : 70)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let cameras = ["Osmo Action 5 Pro", "Osmo Action 4", "Osmo Pocket 3", "Osmo 360", "iPhone", "BOKKI CAM"]
    static let profiles = ["D-Log M", "D-Log", "HLG", "Normal", "Rec.709"]
    static let whiteBalances = ["Auto", "2800K", "3200K", "4000K", "5000K", "5600K", "6500K", "7500K"]
    static let isos = ["ISO 100", "ISO 200", "ISO 400", "ISO 800", "ISO 1600", "ISO 3200"]

    /// Scene / take number with − and + on either side.
    private func counter(_ label: String, value: Binding<Int>, size: CGFloat) -> some View {
        HStack(spacing: 8) {
            Button { value.wrappedValue = max(1, value.wrappedValue - 1) } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
            }
            Text("\(label) \(value.wrappedValue)")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Button { value.wrappedValue += 1 } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
        }
        .buttonStyle(.borderless)
    }

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

/// Slate value picked from presets in a dropdown on the slate itself.
private struct SlatePickerField: View {
    let prompt: String
    @Binding var text: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { text = option } label: {
                    if option == text { Label(option, systemImage: "checkmark") } else { Text(option) }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(text.isEmpty ? prompt : text).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
            }
            .foregroundStyle(.white)
        }
    }
}
