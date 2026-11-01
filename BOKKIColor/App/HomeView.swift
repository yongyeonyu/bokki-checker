import SwiftUI

struct HomeView: View {
    @State private var store = CustomChartStore()
    @State private var presented: ChartItem?
    @State private var showCheck = false
    @State private var calibrating = false
    @State private var showSettings = false
    @State private var importing = false
    @State private var importError: String?
    @State private var renaming: PatchChart?
    @State private var renameText = ""
    @State private var deleting: PatchChart?

    /// Ids of every built-in chart; tuned charts filed under one of these are shown nested under it.
    private static let builtInIDs = Set(ChartCatalog.categories(custom: []).flatMap { $0.items.map(\.id) })

    /// Imported charts, plus tuned charts whose original is no longer in the catalog.
    private var looseCustom: [PatchChart] {
        store.charts.filter { $0.baseID.map { !Self.builtInIDs.contains($0) } ?? true }
    }

    private var categories: [ChartCategory] { ChartCatalog.categories(custom: looseCustom) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showCheck = true } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("촬영 전 디스플레이 점검").font(.headline)
                                Text("True Tone · Night Shift · 자동 밝기 끄기 — 항상 같은 색을 내기 위한 필수 단계")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "checklist") }
                    }
                    Button { calibrating = true } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("BOKKI CAM 캘리브레이션").font(.headline)
                                Text("근처의 BOKKI CAM과 연결 — 카메라가 요청하는 체커·색상을 전체 화면으로 표시")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "camera.aperture") }
                    }
                }
                ForEach(categories) { cat in
                    Section {
                        ForEach(cat.items) { item in
                            if cat.id == "custom", let chart = looseCustom.first(where: { $0.id == item.id }) {
                                customRow(chart, nested: false)
                            } else {
                                Button { presented = item } label: { ChartRow(item: item) }
                                // Tuned copies sit under their original, like a folder.
                                ForEach(store.children(of: item.id)) { customRow($0, nested: true) }
                            }
                        }
                        if cat.id == "custom" {
                            Button { importing = true } label: { Label("CSV / CGATS 파일 가져오기", systemImage: "plus") }
                        }
                    } header: {
                        Label(cat.title, systemImage: cat.symbol)
                    } footer: {
                        Text(cat.summary)
                    }
                }
                Section("데이터 출처") {
                    Text("X-Rite (2016) ColorChecker Classic/SG 공식 사양, BabelColor 평균값, Image Engineering TE226 V2 — colour-science 데이터셋(BSD-3) 경유. Monk Skin Tone Scale © Google, CC BY 4.0. ColorChecker는 X-Rite/Calibrite의 상표이며 본 앱은 호환 레퍼런스 값을 표시합니다. 'BOKKI 참고값' 표기는 자체 정의값입니다.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("BOKKI Checker")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .fullScreenCover(item: $presented) { ChartScreen(item: $0).environment(store) }
        #if DEBUG
        // App Store captures: `-openChart <id>` opens that chart at launch.
        .onAppear {
            guard let id = UserDefaults.standard.string(forKey: "openChart") else { return }
            presented = categories.flatMap(\.items).first { $0.id == id }
        }
        #endif
        .sheet(isPresented: $showCheck) { DisplayCheckView() }
        .fullScreenCover(isPresented: $calibrating) { CalibrationScreen().environment(store) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
            do {
                let url = try result.get()
                try store.importFile(url)
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("이름 변경", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("이름", text: $renameText)
            Button("저장") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if let id = renaming?.id, !name.isEmpty { store.rename(id: id, to: name) }
                renaming = nil
            }
            Button("취소", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("이 커스텀 체커를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let id = deleting?.id { store.remove(id: id) }
                deleting = nil
            }
            Button("취소", role: .cancel) { deleting = nil }
        } message: {
            Text(deleting?.title ?? "")
        }
        .alert("가져오기 실패", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(importError ?? "") }
    }
}

extension HomeView {
    /// A saved custom chart: tap to open, trailing menu to edit colours, rename or delete.
    @ViewBuilder
    fileprivate func customRow(_ chart: PatchChart, nested: Bool) -> some View {
        HStack(spacing: 8) {
            Button { presented = ChartItem(chart) } label: {
                HStack(spacing: 8) {
                    if nested {
                        Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary).font(.footnote)
                    }
                    ChartRow(item: ChartItem(chart))
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Menu {
                Button { presented = ChartItem(chart) } label: { Label("색상 편집", systemImage: "slider.horizontal.3") }
                Button { renameText = chart.title; renaming = chart } label: { Label("이름 변경", systemImage: "pencil") }
                Button(role: .destructive) { deleting = chart } label: { Label("삭제", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
        }
        .padding(.leading, nested ? 24 : 0)
    }
}

struct ChartRow: View {
    let item: ChartItem
    @AppStorage(SettingsKey.outputSpace) private var space: OutputSpace = .displayP3

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 64, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case let .patches(chart):
            PatchGridView(chart: chart, space: space, aspect: .fill, surround: .black).allowsHitTesting(false)
        case .slate:
            PatchGridView(chart: ChartCatalog.cc24, space: space, aspect: .fill, surround: .black).allowsHitTesting(false)
        case let .pattern(kind):
            PatternView(kind: kind, space: space).allowsHitTesting(false)
        }
    }
}
