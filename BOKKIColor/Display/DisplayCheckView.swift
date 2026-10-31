import SwiftUI

/// Pre-shoot checklist for display settings an app cannot change itself.
struct DisplayCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lock = DisplayLock()
    @State private var checked: Set<Int> = []

    private let items: [(String, String, String)] = [
        ("True Tone 끄기", "설정 › 디스플레이 및 밝기 › True Tone", "주변광에 따라 화이트포인트가 바뀌어 매번 색이 달라집니다."),
        ("Night Shift 끄기", "설정 › 디스플레이 및 밝기 › Night Shift", "예약 시간에 화면이 노랗게 변합니다."),
        ("자동 밝기 끄기", "설정 › 손쉬운 사용 › 디스플레이 및 텍스트 크기 › 자동 밝기", "앱이 100%로 고정하지만 자동 밝기가 다시 낮출 수 있습니다."),
        ("화이트 포인트 줄이기 끄기", "설정 › 손쉬운 사용 › 디스플레이 및 텍스트 크기", "밝은 색의 세기를 줄여 하이라이트가 어두워집니다."),
        ("색상 필터 / 반전 끄기", "설정 › 손쉬운 사용 › 디스플레이 및 텍스트 크기", "모든 색이 바뀝니다."),
        ("레퍼런스 모드 (iPad Pro)", "설정 › 디스플레이 및 밝기 › 고급 › 레퍼런스 모드", "지원 기기에서 켜면 가장 정확한 P3/SDR 출력이 됩니다. 켜면 밝기 고정이 기기 정책에 따릅니다."),
        ("저전력 모드 끄기 · 충전 연결", "제어 센터 / 설정 › 배터리", "저전력·과열 시 시스템이 최대 밝기를 제한합니다."),
        ("보호필름·반사 제거", "무광/블루라이트 필름은 색을 바꿉니다", "화면을 정면에서, 주변 조명이 비치지 않게 촬영하세요."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("현재 밝기", value: "\(Int(UIScreen.main.brightness * 100))%")
                    LabeledContent("체커 화면 밝기", value: "자동 100% 고정")
                    if lock.warnings.isEmpty {
                        Label("감지된 문제 없음", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        ForEach(lock.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                } header: { Text("자동 점검") } footer: {
                    Text("True Tone · Night Shift · 자동 밝기는 iOS가 앱에 상태를 알려주지 않으므로 아래에서 직접 확인하세요.")
                }
                Section("수동 점검") {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        Button {
                            if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: checked.contains(i) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(i) ? .green : .secondary).font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.0).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(item.1).font(.caption).foregroundStyle(.blue)
                                    Text(item.2).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("설정 앱 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            .navigationTitle("디스플레이 점검")
            .toolbar { Button("완료") { dismiss() } }
            .onAppear { lock.refreshWarnings() }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.outputSpace) private var space: OutputSpace = .displayP3
    @AppStorage(SettingsKey.aspect) private var aspectRaw = AspectMode.physical.rawValue
    @AppStorage(SettingsKey.surround) private var surroundRaw = Surround.black.rawValue
    @AppStorage(SettingsKey.lockBrightness) private var lockBrightness = true
    @AppStorage(SettingsKey.autoRotate) private var autoRotate = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("출력 색공간", selection: $space) { ForEach(OutputSpace.allCases) { Text($0.title).tag($0) } }
                } footer: {
                    Text("Display P3 권장: 24색 전체를 클립 없이 표시합니다. sRGB에서는 일부 패치(예: cyan)가 개멋 밖이라 클립됩니다. 두 모드 모두 D65 화이트·sRGB 전달함수를 사용합니다.")
                }
                Section {
                    Toggle("체커 화면에서 밝기 100% 고정", isOn: $lockBrightness)
                } footer: {
                    Text("켜면 체커를 여는 동안 밝기를 최대로 유지하고(사용자가 바꿔도 즉시 복귀), 화면 꺼짐을 막습니다. 닫으면 원래 밝기로 돌아갑니다.")
                }
                Section("체커 표시") {
                    Picker("비율", selection: $aspectRaw) { ForEach(AspectMode.allCases) { Text($0.title).tag($0.rawValue) } }
                    Picker("주변색", selection: $surroundRaw) { ForEach(Surround.allCases) { Text($0.title).tag($0.rawValue) } }
                    Toggle("세로 화면에서 가로형 체커 90° 회전", isOn: $autoRotate)
                }
            }
            .navigationTitle("설정")
            .toolbar { Button("완료") { dismiss() } }
        }
    }
}
