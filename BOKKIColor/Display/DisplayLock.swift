import SwiftUI
import UIKit

enum AspectMode: String, CaseIterable, Identifiable {
    case physical, fill
    var id: String { rawValue }
    var title: String { self == .physical ? "실물 비율" : "화면 꽉 채움" }
}

enum Surround: String, CaseIterable, Identifiable {
    case black, gray18, white
    var id: String { rawValue }
    var title: String {
        switch self {
        case .black: "블랙"
        case .gray18: "18% 그레이"
        case .white: "화이트"
        }
    }
    var spec: ColorSpec {
        switch self {
        case .black: .gray(0)
        case .gray18: GeneratedCharts.gray18
        case .white: .gray(1)
        }
    }
}

/// Keys shared by every view that reads display settings.
enum SettingsKey {
    static let outputSpace = "outputSpace"
    static let aspect = "aspectMode"
    static let surround = "surround"
    static let lockBrightness = "lockBrightness"
    static let sequenceInterval = "sequenceInterval"
    static let autoRotate = "autoRotate"
    static let shortcutName = "display.shortcutName"
    static let restoreShortcutName = "display.restoreShortcutName"
    static let autoRunShortcut = "display.autoRunShortcut"
    static let autoRunRestore = "display.autoRunRestore"
}

/// Runs the user's Shortcuts shortcuts that switch display settings iOS won't let an app change.
enum DisplayShortcut {
    static let defaultName = "BOKKI 촬영 모드"
    static let defaultRestoreName = "BOKKI 촬영 종료"

    /// Runs a shortcut by name; Shortcuts comes back to this app when it finishes.
    @MainActor
    static func run(_ name: String) {
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        c.queryItems = [URLQueryItem(name: "name", value: name),
                        URLQueryItem(name: "x-success", value: "bokkichecker://"),
                        URLQueryItem(name: "x-cancel", value: "bokkichecker://"),
                        URLQueryItem(name: "x-error", value: "bokkichecker://")]
        if let url = c.url { UIApplication.shared.open(url) }
    }
}

/// Keeps the screen at full brightness and awake while a chart is shown so every capture sees
/// the same emitted light. Restores the user's brightness when the chart closes.
@MainActor
@Observable
final class DisplayLock {
    private(set) var isActive = false
    private(set) var warnings: [String] = []
    private var savedBrightness: CGFloat?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    static let target: CGFloat = 1.0

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    func start(lockBrightness: Bool) {
        guard !isActive else { return }
        isActive = true
        UIApplication.shared.isIdleTimerDisabled = true
        if lockBrightness, let screen {
            savedBrightness = screen.brightness
            screen.brightness = Self.target
            let nc = NotificationCenter.default
            // Re-apply when the user or the system changes brightness, or when we return to foreground.
            for name in [UIScreen.brightnessDidChangeNotification, UIApplication.didBecomeActiveNotification] {
                observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reapply() }
                })
            }
        }
        refreshWarnings()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWarnings() }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        if let savedBrightness, let screen { screen.brightness = savedBrightness }
        savedBrightness = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func reapply() {
        guard isActive, savedBrightness != nil, let screen, abs(screen.brightness - Self.target) > 0.005 else { return }
        screen.brightness = Self.target
    }

    /// Conditions that change emitted colour or brightness and that the app can detect.
    func refreshWarnings() {
        var w: [String] = []
        // The simulator cannot change brightness, so the check only applies on a device.
        #if !targetEnvironment(simulator)
        if savedBrightness != nil, let screen, screen.brightness < Self.target - 0.01 {
            w.append(String(format: "밝기 %.0f%% (100%%가 아님)", screen.brightness * 100))
        }
        #endif
        if ProcessInfo.processInfo.isLowPowerModeEnabled { w.append("저전력 모드: 밝기 제한 가능") }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: w.append("기기 과열: 화면 감광 중일 수 있음")
        default: break
        }
        if UIAccessibility.isInvertColorsEnabled { w.append("색상 반전 켜짐") }
        if UIAccessibility.isGrayscaleEnabled { w.append("흑백(색상 필터) 켜짐") }
        if UIAccessibility.isDarkerSystemColorsEnabled { w.append("대비 증가 켜짐") }
        warnings = w
    }
}
