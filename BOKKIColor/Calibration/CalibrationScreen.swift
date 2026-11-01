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
        .overlay(alignment: .topTrailing) {
            if link.frame == nil || showClose {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.title3.bold()).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
                }
                .padding(24)
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
                ProgressView().tint(.white).scaleEffect(1.4)
                Text("BOKKI CAM 연결 대기 중").font(.title2.bold())
                Text("다른 기기에서 BOKKI CAM을 열고 캘리브레이션을 시작하세요.\n두 기기는 가까이 두기만 하면 됩니다 (Bluetooth · Wi-Fi 켜기).")
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
            Text("True Tone · Night Shift · 자동 밝기를 끄고, 화면에 조명이 비치지 않게 두세요.")
                .font(.footnote).foregroundStyle(.orange).padding(.top, 12)
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
                // Fiducials: white squares in the corners (protocol: 0.06 × short side, inset 0.02).
                let f = 0.06 * short, inset = 0.02 * short
                for origin in [CGPoint(x: inset, y: inset), CGPoint(x: size.width - inset - f, y: inset),
                               CGPoint(x: size.width - inset - f, y: size.height - inset - f),
                               CGPoint(x: inset, y: size.height - inset - f)] {
                    ctx.fill(Path(CGRect(origin: origin, size: CGSize(width: f, height: f))), with: .color(.white))
                }
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
}
