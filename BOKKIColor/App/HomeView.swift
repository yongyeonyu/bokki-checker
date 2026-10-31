import SwiftUI

struct HomeView: View {
    @State private var store = CustomChartStore()
    @State private var presented: ChartItem?
    @State private var showCheck = false
    @State private var showSettings = false
    @State private var importing = false
    @State private var importError: String?

    private var categories: [ChartCategory] { ChartCatalog.categories(custom: store.charts) }

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
                }
                ForEach(categories) { cat in
                    Section {
                        ForEach(cat.items) { item in
                            Button { presented = item } label: { ChartRow(item: item) }
                        }
                        .onDelete(perform: cat.id == "custom" ? { store.remove(at: $0) } : nil)
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
        .sheet(isPresented: $showCheck) { DisplayCheckView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
            do {
                let url = try result.get()
                try store.importFile(url)
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("가져오기 실패", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(importError ?? "") }
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
