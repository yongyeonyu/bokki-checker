import Foundation
import Observation

enum ImportError: LocalizedError {
    case empty, unreadable
    var errorDescription: String? {
        switch self {
        case .empty: "패치 데이터를 찾지 못했습니다. 'name,L,a,b' 형식의 CSV 또는 LAB_L/LAB_A/LAB_B 필드가 있는 CGATS 파일을 사용하세요."
        case .unreadable: "파일을 읽을 수 없습니다."
        }
    }
}

/// User-imported charts, persisted as JSON in the app's Documents folder.
@MainActor
@Observable
final class CustomChartStore {
    private(set) var charts: [PatchChart] = []
    private let url = URL.documentsDirectory.appending(path: "custom_charts.json")

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([PatchChart].self, from: data) {
            charts = saved
        }
    }

    func importFile(_ file: URL) throws {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        guard let text = (try? String(contentsOf: file, encoding: .utf8)) ?? (try? String(contentsOf: file, encoding: .isoLatin1)) else {
            throw ImportError.unreadable
        }
        let title = file.deletingPathExtension().lastPathComponent
        guard let chart = Self.parse(text, title: title) else { throw ImportError.empty }
        charts.append(chart)
        save()
    }

    /// Adds a chart, or replaces the stored chart with the same id.
    func save(_ chart: PatchChart) {
        if let i = charts.firstIndex(where: { $0.id == chart.id }) { charts[i] = chart } else { charts.append(chart) }
        save()
    }

    func remove(at offsets: IndexSet) {
        charts.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        try? JSONEncoder().encode(charts).write(to: url, options: .atomic)
    }

    /// Accepts CGATS (BEGIN_DATA_FORMAT … BEGIN_DATA … END_DATA) with LAB_* or RGB_* fields,
    /// or CSV lines `name,v1,v2,v3`. CSV mode is chosen by an optional first line:
    /// `LAB` (default, D50), `RGB` (sRGB 0–255) or `P3` (Display P3 0–255). `#columns=N` sets the grid width.
    nonisolated static func parse(_ text: String, title: String) -> PatchChart? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var patches: [Patch] = []
        var columns = 6

        if let fmtStart = lines.firstIndex(of: "BEGIN_DATA_FORMAT"), let dataStart = lines.firstIndex(of: "BEGIN_DATA") {
            let fields = lines[(fmtStart + 1)..<(lines.firstIndex(of: "END_DATA_FORMAT") ?? dataStart)]
                .flatMap { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) }
            func idx(_ n: String) -> Int? { fields.firstIndex(of: n) }
            let nameIdx = idx("SAMPLE_NAME") ?? idx("SAMPLE_ID")
            let end = lines.firstIndex(of: "END_DATA") ?? lines.count
            for line in lines[(dataStart + 1)..<end] {
                let v = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                func d(_ i: Int?) -> Double? { i.flatMap { v.indices.contains($0) ? Double(v[$0]) : nil } }
                let name = nameIdx.flatMap { v.indices.contains($0) ? v[$0] : nil } ?? "\(patches.count + 1)"
                if let l = d(idx("LAB_L")), let a = d(idx("LAB_A")), let b = d(idx("LAB_B")) {
                    patches.append(Patch(name: name, spec: .lab(l, a, b), reference: String(format: "L* %.2f a* %.2f b* %.2f", l, a, b)))
                } else if let r = d(idx("RGB_R")), let g = d(idx("RGB_G")), let b = d(idx("RGB_B")) {
                    let s = max(r, g, b) > 1 ? 255.0 : 1
                    patches.append(Patch(name: name, spec: .encoded(Vec3(r, g, b) / s, space: .sRGB), reference: "sRGB \(Int(r)) \(Int(g)) \(Int(b))"))
                }
            }
            columns = patches.count == 24 ? 6 : patches.count == 140 ? 14 : patches.count == 45 ? 9 : min(10, max(1, Int(Double(patches.count).squareRoot().rounded(.up))))
        } else {
            var mode = "LAB"
            for line in lines {
                let upper = line.uppercased()
                if ["LAB", "RGB", "P3"].contains(upper) { mode = upper; continue }
                if upper.hasPrefix("#COLUMNS=") { columns = Int(line.dropFirst(9)) ?? columns; continue }
                if line.hasPrefix("#") { continue }
                let parts = line.split(separator: line.contains(";") ? ";" : ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 4, let x = Double(parts[1]), let y = Double(parts[2]), let z = Double(parts[3]) else { continue }
                switch mode {
                case "RGB": patches.append(Patch(name: parts[0], spec: .encoded(Vec3(x, y, z) / 255, space: .sRGB), reference: "sRGB \(Int(x)) \(Int(y)) \(Int(z))"))
                case "P3": patches.append(Patch(name: parts[0], spec: .encoded(Vec3(x, y, z) / 255, space: .displayP3), reference: "P3 \(Int(x)) \(Int(y)) \(Int(z))"))
                default: patches.append(Patch(name: parts[0], spec: .lab(x, y, z), reference: String(format: "L* %.2f a* %.2f b* %.2f", x, y, z)))
                }
            }
        }
        guard !patches.isEmpty else { return nil }
        columns = max(1, min(columns, patches.count))
        return PatchChart(id: "custom_\(UUID().uuidString)", title: title, subtitle: "\(patches.count)패치 · 가져온 체커",
                          rows: (patches.count + columns - 1) / columns, columns: columns, patches: patches, source: "사용자 가져오기")
    }
}
