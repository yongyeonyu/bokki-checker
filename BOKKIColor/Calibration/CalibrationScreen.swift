import CoreImage.CIFilterBuiltins
import SwiftUI

/// Full-screen calibration target that BOKKI CAM drives over the link. While idle it shows the
/// connection state; while a target is up nothing else is drawn, so the camera sees only the target.
struct CalibrationScreen: View {
    @Environment(\.dismiss) private var dismiss
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
                } else {
                    // The corner markers stay up while waiting, so the camera can be framed first.
                    fiducials(size: geo.size)
                    status
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
            if link.frame == nil || showClose {
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
    }

    private var status: some View {
        VStack(spacing: 16) {
            switch link.state {
            case .waiting:
                Text("BOKKI CAM 연결 대기 중").font(.title2.bold())
                if let qr = Self.qrImage(link.pairingURL.absoluteString) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("BOKKI CAM 연결 QR 코드")
                }
                Text("연결 코드 \(link.pairingCode)").font(.system(.title3, design: .monospaced).bold())
                Text("아이폰 카메라나 BOKKI CAM으로 QR을 찍으면 바로 연결됩니다.\n또는 BOKKI CAM에서 캘리브레이션을 시작하세요 (Bluetooth · Wi-Fi 켜기).")
                    .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
            case .connected(let name):
                Image(systemName: "link.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("\(name) 연결됨").font(.title2.bold())
                Text("BOKKI CAM이 타깃을 띄울 때까지 화면을 카메라 쪽으로 두세요.")
                    .foregroundStyle(.white.opacity(0.7))
            case .finished(let name):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("캘리브레이션 완료").font(.title2.bold())
                Text("\(name)에서 결과를 확인하세요.").foregroundStyle(.white.opacity(0.7))
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
            }
        }
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
