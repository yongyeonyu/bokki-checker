import CoreImage.CIFilterBuiltins
import SwiftUI

/// Full-screen calibration target that BOKKI CAM drives over the link. While idle it shows the
/// connection state; while a target is up nothing else is drawn, so the camera sees only the target.
struct CalibrationScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CustomChartStore.self) private var store
    @State private var link = CalibrationLink()
    @State private var lock = DisplayLock()
    @State private var showClose = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let frame = link.frame {
                    target(frame, size: geo.size)
                    if let notice = lostNotice {
                        lostPanel(notice)
                    }
                } else if let result = link.result {
                    CalibrationResultView(result: result) { link.dismissResult() }
                } else {
                    // The corner markers stay up while waiting, so the camera can be framed first.
                    fiducials(size: geo.size)
                    status(size: geo.size)
                }
            }
            .onAppear { link.canvasSize = geo.size }
            .onChange(of: geo.size) { _, size in link.canvasSize = size }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { if link.frame != nil { showClose.toggle() } }
        .overlay(alignment: .bottom) {
            if (link.frame == nil && link.result == nil) || showClose {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.title3.bold()).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
                }
                .padding(.bottom, 48)
                .accessibilityLabel("닫기")
            }
        }
        .onAppear {
            link.chartLookup = { id in ChartCatalog.references[id] ?? store.charts.first { $0.id == id } }
            link.availableCharts = {
                ChartCatalog.referenceIDs + store.charts.filter { $0.layoutRects == nil }.map(\.id)
            }
            link.start()
            lock.start(lockBrightness: true)
        }
        .onDisappear {
            link.stop()
            lock.stop()
        }
        .onChange(of: link.frame == nil) { _, _ in showClose = false }
        .onChange(of: scenePhase) { _, phase in if phase == .active { link.resume() } }
    }

    /// Shown over the target only once the camera is gone or silent, so it never spoils a shot.
    private var lostNotice: String? {
        if case .reconnecting(let name) = link.state { return "\(name) 연결이 끊겼습니다. 다시 연결을 기다리는 중…" }
        if link.stalled { return "BOKKI CAM 응답이 없습니다. BOKKI CAM에서 캘리브레이션이 멈췄거나 끝났을 수 있습니다." }
        return nil
    }

    private func lostPanel(_ notice: String) -> some View {
        VStack(spacing: 14) {
            Label(notice, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold)).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("새 QR로 다시 연결") { link.restart() }
                    .buttonStyle(.borderedProminent)
                Button("닫기") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 520)
        .padding(40)
    }

    private func status(size: CGSize) -> some View {
        VStack(spacing: 16) {
            switch link.state {
            case .waiting:
                if let name = link.lastFinished {
                    Label("\(name) 캘리브레이션 완료 — 결과는 BOKKI CAM에서 확인하세요.", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(.green)
                }
                Text("BOKKI CAM 연결 대기 중").font(.title2.bold())
                // Big enough for BOKKI CAM to read from about 1 m; white quiet zone around the code.
                let side = min(min(size.width, size.height) * 0.5, max(size.width, size.height) * 0.36)
                if let qr = Self.qrImage(link.pairingPayload) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                        .frame(width: side, height: side)
                        .padding(side * 0.08).background(.white)
                        .accessibilityLabel("BOKKI CAM 연결 QR 코드")
                }
                Text("BOKKI CAM 사진 화면에 이 QR을 비추면 이 화면에 바로 연결됩니다.\n또는 BOKKI CAM에서 캘리브레이션을 시작하세요 (Bluetooth · Wi-Fi 켜기).")
                    .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
            case .connected(let name):
                Image(systemName: "link.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("\(name) 연결됨").font(.title2.bold())
                Text("BOKKI CAM이 타깃을 띄울 때까지 화면을 카메라 쪽으로 두세요.")
                    .foregroundStyle(.white.opacity(0.7))
            case .reconnecting(let name):
                ProgressView().tint(.white).controlSize(.large)
                Text("\(name) 재연결 대기 중").font(.title2.bold())
                Text("연결이 잠시 끊겼습니다. BOKKI CAM이 자동으로 다시 연결합니다.")
                    .foregroundStyle(.white.opacity(0.7))
            }
            Label("BOKKI CAM 화면에 네 모서리의 흰 사각형이 모두 들어오게 맞추세요. 화면을 정면에서, 프레임을 거의 채우게 찍어야 합니다.",
                  systemImage: "viewfinder")
                .font(.callout.weight(.semibold)).multilineTextAlignment(.center).padding(.top, 12)
            Text("True Tone · Night Shift · 자동 밝기를 끄고, 화면을 닦고, 조명이 화면에 비치지 않게 두세요.")
                .font(.footnote).foregroundStyle(.orange)
        }
        .foregroundStyle(.white)
        .padding(40)
    }

    @ViewBuilder
    private func target(_ frame: CalibrationFrame, size: CGSize) -> some View {
        if let flat = frame.flat {
            // Only the colour, edge to edge: no progress text on flats (the CAM finds the screen from them).
            Color(.displayP3, red: flat.x, green: flat.y, blue: flat.z)
        } else if let chart = frame.chart {
            Canvas { ctx, size in
                let short = min(size.width, size.height)
                Self.drawFiducials(in: &ctx, size: size)
                // Same geometry BOKKI CAM uses to find the patches.
                let margin = CalibrationProtocol.marginFraction * short
                let g = CalibrationProtocol.gapFraction
                let cols = Double(chart.columns), rows = Double(chart.rows)
                let pw = (size.width - 2 * margin) / (cols + (cols - 1) * g)
                let ph = (size.height - 2 * margin) / (rows + (rows - 1) * g)
                for (i, patch) in chart.patches.enumerated() {
                    let r = Double(i / chart.columns), c = Double(i % chart.columns)
                    let rect = CGRect(x: margin + c * pw * (1 + g), y: margin + r * ph * (1 + g), width: pw, height: ph)
                    ctx.fill(Path(rect), with: .color(patch.spec.color(in: .displayP3)))
                }
                if let text = Self.progressText(frame.step) {
                    Self.drawProgress(text, in: &ctx, size: size)
                }
            }
        }
    }

    /// `index / total · Phase · label` (+ a retake note), from whatever parts of `step` the CAM sent.
    private static func progressText(_ step: CalibrationStep?) -> String? {
        guard let step else { return nil }
        var parts: [String] = []
        if let i = step.index {
            parts.append(step.total.map { "\(i) / \($0)" } ?? "\(i)")
        }
        if let phase = step.phase, !phase.isEmpty { parts.append(phase.prefix(1).uppercased() + phase.dropFirst()) }
        if let label = step.label, !label.isEmpty { parts.append(label) }
        if step.retake == true { parts.append("Retake — hold still") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Progress in the top black margin, between the corner markers and above the patches: the
    /// band from 0.02 to 0.08 × short side tall, from 0.1 × short side in from each end.
    private static func drawProgress(_ text: String, in ctx: inout GraphicsContext, size: CGSize) {
        let short = min(size.width, size.height)
        let band = CGRect(x: 0.1 * short, y: 0.02 * short, width: size.width - 0.2 * short, height: 0.06 * short)
        guard band.width > 0 else { return }
        let label = Text(text).font(.system(size: 0.03 * short, weight: .semibold)).foregroundStyle(Color(white: 0.5))
        var inner = ctx
        inner.clip(to: Path(band))
        inner.draw(inner.resolve(label), at: CGPoint(x: band.midX, y: band.midY), anchor: .center)
    }

    /// QR code bitmap for the pairing URL (black on white, one pixel per module; scaled up without smoothing).
    private static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func fiducials(size: CGSize) -> some View {
        Canvas { ctx, size in Self.drawFiducials(in: &ctx, size: size) }
    }

    /// White squares in the corners (protocol: 0.06 × short side, inset 0.02) that BOKKI CAM finds.
    private static func drawFiducials(in ctx: inout GraphicsContext, size: CGSize) {
        let short = min(size.width, size.height)
        let f = 0.06 * short, inset = 0.02 * short
        for origin in [CGPoint(x: inset, y: inset), CGPoint(x: size.width - inset - f, y: inset),
                       CGPoint(x: size.width - inset - f, y: size.height - inset - f),
                       CGPoint(x: inset, y: size.height - inset - f)] {
            ctx.fill(Path(CGRect(origin: origin, size: CGSize(width: f, height: f))), with: .color(.white))
        }
    }
}

/// CALIBV2-1101 result from BOKKI CAM: averages and a per-patch list, until the user taps Done.
private struct CalibrationResultView: View {
    let result: CalibrationResult
    let done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Calibration result").font(.title.bold())
                Text(result.look ?? "—").font(.title3)
                Text("Focus: \(focus)").foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 28) {
                stat("Average ΔE", "\(Self.number(result.averageBefore)) → \(Self.number(result.averageAfter))")
                stat("Skin average after", Self.number(result.skinAverageAfter))
                stat("Verify average after", Self.number(result.verifyAverageAfter))
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array((result.patches ?? []).enumerated()), id: \.offset) { _, patch in
                        row(patch)
                        Divider().overlay(.white.opacity(0.15))
                    }
                }
            }
            .frame(maxWidth: 640)
            Button("Done", action: done)
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32).padding(.vertical, 48)
    }

    private var focus: String {
        switch result.focus {
        case "skin": "Skin"
        case "balanced": "Balanced"
        case let other: other ?? "—"
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func row(_ patch: CalibrationResult.Patch) -> some View {
        HStack(spacing: 12) {
            swatch(patch.p3)
            Text(patch.name ?? "—")
            if patch.skin == true {
                Text("Skin").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.3), in: Capsule())
            }
            Spacer()
            Text("\(Self.number(patch.before)) → \(Self.number(patch.after))").monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func swatch(_ p3: [Double]?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        if let p3, p3.count == 3 {
            shape.fill(Color(.displayP3, red: p3[0], green: p3[1], blue: p3[2])).frame(width: 28, height: 28)
        } else {
            shape.stroke(.white.opacity(0.3)).frame(width: 28, height: 28)
        }
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }
}
