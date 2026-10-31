import SwiftUI

/// Full-screen chart presenter. Controls and overlays show on tap and hide 1 s later.
/// Tapping a patch while they are visible opens its values.
struct ChartScreen: View {
    let item: ChartItem
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.outputSpace) private var space: OutputSpace = .displayP3
    @AppStorage(SettingsKey.aspect) private var aspectRaw = AspectMode.physical.rawValue
    @AppStorage(SettingsKey.surround) private var surroundRaw = Surround.black.rawValue
    @AppStorage(SettingsKey.lockBrightness) private var lockBrightness = true
    @AppStorage(SettingsKey.sequenceInterval) private var interval = 2.0
    @AppStorage(SettingsKey.autoRotate) private var autoRotate = true

    @State private var lock = DisplayLock()
    @State private var showControls = true
    @State private var showLabels = false
    @State private var selected: Patch?
    @State private var sequence = false
    @State private var seqIndex = 0
    @State private var seqPaused = false
    /// Editable copy of the chart; differs from the item's chart once a patch is tuned.
    @State private var working: PatchChart?
    @State private var saving = false
    @State private var saveName = ""
    @State private var savedNotice = false
    /// Pending auto-hide; replaced on every interaction.
    @State private var hideTask: Task<Void, Never>?
    /// True while the settings menu is open, so the controls stay up until the user taps the chart.
    @State private var pinned = false
    @Environment(CustomChartStore.self) private var store

    private var originalChart: PatchChart? { if case let .patches(c) = item.kind { c } else { nil } }
    private var isTuned: Bool { working != nil && working != originalChart }

    private var aspect: AspectMode { AspectMode(rawValue: aspectRaw) ?? .physical }
    private var surround: Surround { Surround(rawValue: surroundRaw) ?? .black }

    var body: some View {
        ZStack {
            chartContent
                .ignoresSafeArea()
                .onTapGesture { if showControls { hideNow() } else { reveal() } }
            if showControls {
                controls
                if !lock.warnings.isEmpty { warningBadge }
            }
        }
        .simultaneousGesture(
            // Swipe down to close; a mostly vertical drag of at least 120 pt.
            DragGesture(minimumDistance: 40).onEnded { v in
                if v.translation.height > 120, abs(v.translation.width) < v.translation.height { dismiss() }
            }
        )
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if working == nil { working = originalChart }
            lock.start(lockBrightness: lockBrightness)
            reveal()
        }
        .onDisappear {
            hideTask?.cancel()
            lock.stop()
        }
        .onChange(of: selected) { _, new in if new == nil { reveal() } }
        .onChange(of: saving) { _, now in if !now { reveal() } }
        .onChange(of: space) { _, _ in pinned = false; scheduleHide() }
        .onChange(of: aspectRaw) { _, _ in pinned = false; scheduleHide() }
        .onChange(of: surroundRaw) { _, _ in pinned = false; scheduleHide() }
        .sheet(item: $selected) { patch in
            detail(for: patch).presentationDetents([.medium, .large]).presentationBackground(Color(.systemBackground))
        }
        .alert("커스텀 체커로 저장", isPresented: $saving) {
            TextField("이름", text: $saveName)
            if originalChart?.id.hasPrefix("custom_") == true {
                Button("덮어쓰기") { save(overwrite: true) }
            }
            Button("새로 저장") { save(overwrite: false) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("튜닝한 색상을 커스텀 체커 목록에 저장합니다. 원본(기본값)은 그대로 유지됩니다.")
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        switch item.kind {
        case let .patches(base):
            let chart = working ?? base
            if sequence {
                SequenceView(chart: chart, space: space, index: $seqIndex, paused: seqPaused, interval: interval)
            } else {
                GeometryReader { geo in
                    let portrait = geo.size.height > geo.size.width
                    let shown = autoRotate && portrait && chart.isLandscape ? chart.rotatedClockwise : chart
                    PatchGridView(chart: shown, space: space, aspect: aspect, surround: surround, showLabels: showLabels) { p in
                        handleTap(p)
                    }
                }
            }
        case let .pattern(kind):
            PatternView(kind: kind, space: space)
        case .slate:
            SlateView(space: space, aspect: aspect, showControls: showControls) { p in
                handleTap(p)
            }
        }
    }

    @ViewBuilder
    private func detail(for patch: Patch) -> some View {
        if let idx = working?.patches.firstIndex(where: { $0.id == patch.id }) {
            PatchDetailView(patch: Binding(get: { working?.patches[idx] ?? patch }, set: { working?.patches[idx] = $0 }),
                            original: originalChart?.patches[idx], editable: true)
        } else {
            PatchDetailView(patch: .constant(patch))
        }
    }

    private func save(overwrite: Bool) {
        guard var chart = working, let base = originalChart else { return }
        let name = saveName.trimmingCharacters(in: .whitespaces)
        chart.title = name.isEmpty ? base.title + " (튜닝)" : name
        if !overwrite {
            chart.id = "custom_\(UUID().uuidString)"
            chart.subtitle = "튜닝 · 기본: \(base.title)"
            chart.source = "BOKKI 튜닝 (기본값: \(base.source.isEmpty ? base.title : base.source))"
            chart.patches = chart.patches.map { var p = $0; p.id = UUID(); return p }
        }
        store.save(chart)
        savedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedNotice = false }
    }

    /// Shows the controls and hides them again 1 s after the last interaction.
    private func reveal() {
        withAnimation(.easeInOut(duration: 0.15)) { showControls = true }
        scheduleHide()
    }

    private func hideNow() {
        hideTask?.cancel()
        pinned = false
        withAnimation(.easeInOut(duration: 0.15)) { showControls = false }
    }

    /// Hides after 1 s, unless a sheet, alert or the settings menu is open.
    private func scheduleHide() {
        hideTask?.cancel()
        guard !pinned, selected == nil, !saving else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            hideNow()
        }
    }

    private func handleTap(_ patch: Patch?) {
        guard let patch else {
            if showControls { hideNow() } else { reveal() }
            return
        }
        if showControls {
            hideTask?.cancel()
            selected = patch
        } else {
            reveal()
        }
    }

    private var isPatches: Bool { if case .patches = item.kind { true } else { false } }

    private var controls: some View {
        VStack {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(.subheadline.bold()).lineLimit(1)
                    Text("\(space.title) · 밝기 \(lockBrightness ? "100% 고정" : "수동")").font(.caption2).opacity(0.8)
                }
                Spacer()
                Menu {
                    Picker("색공간", selection: $space) { ForEach(OutputSpace.allCases) { Text($0.title).tag($0) } }
                    if isPatches || item.kind == .slate {
                        Picker("비율", selection: $aspectRaw) { ForEach(AspectMode.allCases) { Text($0.title).tag($0.rawValue) } }
                    }
                    if isPatches {
                        Picker("주변색", selection: $surroundRaw) { ForEach(Surround.allCases) { Text($0.title).tag($0.rawValue) } }
                    }
                } label: { Image(systemName: "slider.horizontal.3") }
                    .simultaneousGesture(TapGesture().onEnded { pinned = true; hideTask?.cancel() })
                if isPatches {
                    Button { aspectRaw = (aspect == .physical ? AspectMode.fill : .physical).rawValue } label: {
                        Image(systemName: aspect == .physical ? "rectangle.arrowtriangle.2.outward" : "rectangle.arrowtriangle.2.inward")
                    }
                    Button { showLabels.toggle() } label: { Image(systemName: showLabels ? "tag.fill" : "tag") }
                    if isTuned {
                        Button { working = originalChart } label: { Image(systemName: "arrow.uturn.backward") }
                        Button { saveName = ""; saving = true } label: { Image(systemName: "square.and.arrow.down.fill") }
                    }
                    Button { sequence.toggle(); seqIndex = 0; seqPaused = false } label: {
                        Image(systemName: sequence ? "square.grid.2x2" : "play.rectangle")
                    }
                }
            }
            .font(.title3)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 12)
            Spacer()
            if sequence, let chart = working {
                HStack(spacing: 18) {
                    Button { seqIndex = (seqIndex - 1 + chart.patches.count) % chart.patches.count } label: { Image(systemName: "backward.fill") }
                    Button { seqPaused.toggle() } label: { Image(systemName: seqPaused ? "play.fill" : "pause.fill") }
                    Button { seqIndex = (seqIndex + 1) % chart.patches.count } label: { Image(systemName: "forward.fill") }
                    Picker("간격", selection: $interval) {
                        ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { Text("\(Int($0))초").tag($0) }
                    }.pickerStyle(.segmented).frame(width: 180)
                    Button { selected = chart.patches[seqIndex] } label: { Image(systemName: "info.circle") }
                }
                .font(.title3)
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 8)
            } else if savedNotice {
                Label("커스텀 체커에 저장됨", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).padding(8).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 8)
            } else if item.kind != .slate {
                Text(isTuned ? "튜닝 중 · ↩︎ 기본값 복원 · ⤓ 커스텀 저장" : "패치를 탭하면 색상 정보 · 정밀 튜닝 · 화면 탭하면 컨트롤 숨김")
                    .font(.caption).padding(8).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 8)
            }
        }
        .foregroundStyle(.primary)
        .simultaneousGesture(TapGesture().onEnded { if !pinned { scheduleHide() } })
        .transition(.opacity)
    }

    private var warningBadge: some View {
        VStack {
            Label(lock.warnings.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.bold())
                .padding(6)
                .background(Color.orange.opacity(0.9), in: Capsule())
                .foregroundStyle(.black)
                .padding(.top, 64)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// One patch at a time, full screen, with corner fiducials and an index so captures can be sorted.
struct SequenceView: View {
    let chart: PatchChart
    let space: OutputSpace
    @Binding var index: Int
    let paused: Bool
    let interval: Double

    var body: some View {
        let patch = chart.patches[min(index, chart.patches.count - 1)]
        ZStack {
            patch.spec.color(in: space)
            GeometryReader { geo in
                let m = min(geo.size.width, geo.size.height) * 0.06
                ForEach(0..<4, id: \.self) { i in
                    Fiducial().frame(width: m, height: m)
                        .position(x: i % 2 == 0 ? m : geo.size.width - m, y: i < 2 ? m : geo.size.height - m)
                }
                Text(String(format: "%03d", index + 1))
                    .font(.system(size: m * 0.5, weight: .bold, design: .monospaced))
                    .padding(4).background(Color.black).foregroundStyle(.white)
                    .position(x: geo.size.width / 2, y: m)
            }
        }
        .accessibilityIgnoresInvertColors()
        .task(id: "\(index)-\(paused)-\(interval)") {
            guard !paused else { return }
            try? await Task.sleep(for: .seconds(interval))
            if !Task.isCancelled { index = (index + 1) % chart.patches.count }
        }
    }
}

/// Black square with white ring and black centre — easy to find in a capture.
struct Fiducial: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.black)
            Rectangle().fill(Color.white).padding(4)
            Rectangle().fill(Color.black).padding(8)
            Circle().fill(Color.white).padding(14)
        }
    }
}
