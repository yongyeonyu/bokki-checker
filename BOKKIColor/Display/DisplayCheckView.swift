import SwiftUI

/// Pre-shoot checklist for display settings an app cannot change itself.
struct DisplayCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lock = DisplayLock()
    @State private var checked: Set<Int> = []
    @State private var copiedKeyword: String?
    @State private var showGuide = false
    /// Name of the user's Shortcuts shortcut that switches every display setting at once.
    @AppStorage(SettingsKey.shortcutName) private var shortcutName = DisplayShortcut.defaultName
    @AppStorage(SettingsKey.restoreShortcutName) private var restoreName = DisplayShortcut.defaultRestoreName
    @AppStorage(SettingsKey.autoRunShortcut) private var autoRun = false
    @AppStorage(SettingsKey.autoRunRestore) private var autoRestore = false

    private struct Item {
        let title: String
        let path: String
        let note: String
        /// Term to paste into the Settings search box; nil when there is no setting to open.
        let keyword: String?
        /// Settings URL for this item's own page. Newer iOS may ignore the path and open the
        /// Settings home instead, so the keyword is copied as well.
        var url: String = "App-prefs:"
    }

    private let items: [Item] = [
        Item(title: "True Tone 끄기", path: "설정 › 디스플레이 및 밝기 › True Tone", note: "주변광에 따라 화이트포인트가 바뀌어 매번 색이 달라집니다.", keyword: "True Tone", url: "App-prefs:DISPLAY"),
        Item(title: "Night Shift 끄기", path: "설정 › 디스플레이 및 밝기 › Night Shift", note: "예약 시간에 화면이 노랗게 변합니다.", keyword: "Night Shift", url: "App-prefs:DISPLAY&path=BLUE_LIGHT_REDUCTION"),
        Item(title: "자동 밝기 끄기", path: "설정 › 손쉬운 사용 › 디스플레이 및 텍스트 크기 › 자동 밝기", note: "앱이 100%로 고정하지만 자동 밝기가 다시 낮출 수 있습니다.", keyword: "자동 밝기", url: "App-prefs:ACCESSIBILITY&path=DISPLAY_AND_TEXT"),
        Item(title: "화이트 포인트 줄이기 끄기", path: "설정 › 손쉬운 사용 › 디스플레이 및 텍스트 크기", note: "밝은 색의 세기를 줄여 하이라이트가 어두워집니다.", keyword: "화이트 포인트 줄이기", url: "App-prefs:ACCESSIBILITY&path=DISPLAY_AND_TEXT"),
        Item(title: "색상 필터 / 반전 끄기", path: "설정 › 손쉬운 사용 › 디스플레이 및 텍스트 크기", note: "모든 색이 바뀝니다.", keyword: "색상 필터", url: "App-prefs:ACCESSIBILITY&path=DISPLAY_AND_TEXT/DISPLAY_FILTER"),
        Item(title: "레퍼런스 모드 (iPad Pro)", path: "설정 › 디스플레이 및 밝기 › 고급 › 레퍼런스 모드", note: "지원 기기에서 켜면 가장 정확한 P3/SDR 출력이 됩니다. 켜면 밝기 고정이 기기 정책에 따릅니다.", keyword: "레퍼런스 모드", url: "App-prefs:DISPLAY&path=ADVANCED"),
        Item(title: "저전력 모드 끄기 · 충전 연결", path: "제어 센터 / 설정 › 배터리", note: "저전력·과열 시 시스템이 최대 밝기를 제한합니다.", keyword: "저전력 모드", url: "App-prefs:BATTERY_USAGE"),
        Item(title: "보호필름·반사 제거", path: "무광/블루라이트 필름은 색을 바꿉니다", note: "화면을 정면에서, 주변 조명이 비치지 않게 촬영하세요.", keyword: nil),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        DisplayShortcut.run(shortcutName)
                    } label: {
                        Label("디스플레이 한 번에 설정", systemImage: "bolt.badge.checkmark.fill")
                            .font(.headline)
                    }
                    Button { DisplayShortcut.run(restoreName) } label: {
                        Label("원래대로 되돌리기", systemImage: "arrow.uturn.backward")
                    }
                    // Signed shortcut files bundled with the app; the share sheet's 단축어 app imports them.
                    ForEach([shortcutName, restoreName], id: \.self) { name in
                        if let file = Bundle.main.url(forResource: name, withExtension: "shortcut") {
                            ShareLink(item: file) {
                                Label("‘\(name)’ 단축어 자동 추가", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                    Toggle("체커를 열 때 ‘\(shortcutName)’ 자동 실행", isOn: $autoRun)
                    Toggle("체커를 닫을 때 ‘\(restoreName)’ 자동 실행", isOn: $autoRestore)
                    DisclosureGroup("직접 만들기", isExpanded: $showGuide) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("iOS는 앱이 True Tone·Night Shift 같은 설정을 직접 바꾸지 못하게 합니다. 대신 단축어 앱이 바꿀 수 있어서, 아래 단축어를 한 번 만들어 두면 위 버튼 한 번으로 모두 바뀝니다.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("1. 단축어 앱 › 오른쪽 위 + › ‘동작 추가’")
                            Text("2. 동작을 검색해 차례로 추가하고 모두 ‘끔’으로:\n   · True Tone 설정\n   · Night Shift 설정\n   · 저전력 모드 설정\n   · 화이트 포인트 줄이기 설정\n   · 색상 필터 설정")
                            Text("3. ‘밝기 설정’을 추가하고 100%")
                            Text("4. 단축어 이름을 정확히 ‘\(shortcutName)’로 저장")
                            Text("5. (선택) 같은 동작을 ‘켬’으로 바꾼 ‘\(restoreName)’도 만들면 촬영 후 되돌릴 수 있습니다.")
                            Text("자동 밝기는 단축어로도 바꿀 수 없어 설정 › 손쉬운 사용에서 한 번 꺼 두세요.")
                                .font(.caption).foregroundStyle(.orange)
                            Button("단축어 앱 열기") {
                                if let url = URL(string: "shortcuts://create-shortcut") { UIApplication.shared.open(url) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .font(.callout)
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("원클릭 촬영 모드")
                } footer: {
                    Text("처음 한 번 ‘자동 추가’를 누르고 공유 목록에서 ‘단축어’를 고른 뒤 ‘단축어 추가’를 누르세요. True Tone·Night Shift·저전력 모드를 끄고 밝기를 100%로 맞춥니다. 실행이 끝나면 이 앱으로 돌아옵니다. 자동 실행을 켜면 체커를 열고 닫을 때 단축어 앱이 잠깐 나타났다 돌아옵니다.")
                }
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
                Section {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                            } label: {
                                Image(systemName: checked.contains(i) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(i) ? .green : .secondary).font(.title3)
                            }
                            .buttonStyle(.borderless)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.body.weight(.semibold))
                                Text(item.path).font(.caption).foregroundStyle(.blue)
                                Text(item.note).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if let keyword = item.keyword {
                                Button {
                                    openSettings(keyword: keyword, url: item.url)
                                } label: {
                                    Label("설정", systemImage: "arrow.up.forward.app")
                                        .labelStyle(.iconOnly).font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("설정 열기: \(item.title)")
                            }
                        }
                    }
                } header: {
                    Text("수동 점검")
                } footer: {
                    if let copiedKeyword {
                        Text("‘\(copiedKeyword)’를 복사했습니다. 설정 화면 아래 검색창에 붙여넣으면 바로 찾아갑니다.").foregroundStyle(.blue)
                    } else {
                        Text("↗︎를 누르면 설정 앱이 열리고 항목 이름이 복사됩니다. 설정 검색창에 붙여넣어 바로 이동하세요. iOS는 앱이 설정의 특정 화면을 직접 열 수 있게 하지 않습니다.")
                    }
                }
                Section {
                    Button("설정 앱 열기") { openSettings(keyword: nil) }
                }
            }
            .navigationTitle("디스플레이 점검")
            .toolbar { Button("완료") { dismiss() } }
            .onAppear { lock.refreshWarnings() }
        }
    }

    /// Copies the search keyword (when given), then tries the item's own Settings page, then the
    /// Settings home (where the search box finds the item), then this app's own settings page.
    private func openSettings(keyword: String?, url: String = "App-prefs:") {
        if let keyword {
            UIPasteboard.general.string = keyword
            copiedKeyword = keyword
        }
        let candidates = [url, "App-prefs:", UIApplication.openSettingsURLString].compactMap(URL.init(string:))
        func open(_ i: Int) {
            guard i < candidates.count else { return }
            UIApplication.shared.open(candidates[i]) { ok in if !ok { open(i + 1) } }
        }
        open(0)
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
                    Text("Display P3 권장: 24색 전체를 클립 없이 표시합니다. sRGB·Rec.709는 원색이 같아 화면 색이 같고, cyan 패치만 약간 클립됩니다. Rec.709를 고르면 패치 값이 BT.709 감마 코드값(풀/리미티드 레인지)으로 표시되어 카메라의 Rec.709 출력과 바로 비교할 수 있습니다.")
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
