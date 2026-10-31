import SwiftUI

/// Fine adjustment of one patch, either as CIE L*a*b* (D50) or as RGB code values in the output space.
struct PatchTuningSection: View {
    @Binding var patch: Patch
    let original: Patch?
    let space: OutputSpace

    enum Mode: String, CaseIterable, Identifiable {
        case lab = "Lab", rgb8 = "RGB 8비트", rgb16 = "RGB 16비트"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .lab

    var body: some View {
        Section {
            Picker("조정 방식", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            switch mode {
            case .lab:
                let lab = patch.spec.labD50
                ValueRow(label: "L*", value: lab.x, range: 0...100, step: 0.1, format: "%.2f") { setLab(Vec3($0, lab.y, lab.z)) }
                ValueRow(label: "a*", value: lab.y, range: -128...128, step: 0.1, format: "%.2f") { setLab(Vec3(lab.x, $0, lab.z)) }
                ValueRow(label: "b*", value: lab.z, range: -128...128, step: 0.1, format: "%.2f") { setLab(Vec3(lab.x, lab.y, $0)) }
            case .rgb8, .rgb16:
                let maxV = mode == .rgb8 ? 255.0 : 65535.0
                let e = patch.spec.encoded(in: space) * maxV
                let fmt = "%.0f"
                ValueRow(label: "R", value: e.x.rounded(), range: 0...maxV, step: 1, format: fmt) { setRGB(Vec3($0, e.y, e.z) / maxV) }
                ValueRow(label: "G", value: e.y.rounded(), range: 0...maxV, step: 1, format: fmt) { setRGB(Vec3(e.x, $0, e.z) / maxV) }
                ValueRow(label: "B", value: e.z.rounded(), range: 0...maxV, step: 1, format: fmt) { setRGB(Vec3(e.x, e.y, $0) / maxV) }
            }
            if let original, patch.tuned == true {
                Button("이 패치 기본값으로", role: .destructive) { patch = original }
            }
        } header: {
            Text("정밀 튜닝")
        } footer: {
            Text(mode == .lab
                 ? "L*a*b*(D50)를 0.1 단위로 조정합니다. 체커 화면에 바로 반영되며, 상단 '저장'으로 커스텀 체커로 보관하세요."
                 : "\(space.title) 코드값을 직접 지정합니다. 다른 색공간으로 바꾸면 같은 빛이 나도록 자동 변환됩니다.")
        }
    }

    private func setLab(_ v: Vec3) {
        patch.spec = .lab(v.x, v.y, v.z)
        patch.tuned = true
    }

    private func setRGB(_ v: Vec3) {
        patch.spec = .encoded(Vec3(max(0, min(1, v.x)), max(0, min(1, v.y)), max(0, min(1, v.z))), space: space)
        patch.tuned = true
    }
}

/// Slider + stepper + text entry for one channel.
private struct ValueRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let onChange: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(.body, design: .monospaced).bold()).frame(width: 30, alignment: .leading)
                TextField("", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit(commit)
                    .frame(maxWidth: 110)
                Spacer()
                Stepper("", value: Binding(get: { value }, set: { onChange(clamp($0)) }), in: range, step: step).labelsHidden()
            }
            Slider(value: Binding(get: { value }, set: { onChange(clamp(($0 / step).rounded() * step)) }), in: range)
        }
        .onAppear { text = String(format: format, value) }
        .onChange(of: value) { if !focused { text = String(format: format, value) } }
        .onChange(of: focused) { if !focused { commit() } }
    }

    private func clamp(_ v: Double) -> Double { min(range.upperBound, max(range.lowerBound, v)) }

    private func commit() {
        if let v = Double(text.replacingOccurrences(of: ",", with: ".")) { onChange(clamp(v)) }
        text = String(format: format, value)
    }
}
