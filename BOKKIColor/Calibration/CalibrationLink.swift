import Foundation
import Observation
@preconcurrency import MultipeerConnectivity
import UIKit

/// BOKKI CAM ↔ BOKKI Checker calibration link, protocol v1. The wire format is specified in the
/// BOKKI CAM repository, `docs/calibration/CALIB1101-checker-link.md`; these types mirror it field for field.
enum CalibrationProtocol {
    static let version = 1
    static let serviceType = "bokki-calib"
    static let defaultChartID = "cc24_after2014"
    /// Black border around the grid, as a fraction of the screen's shorter side. Larger than the
    /// fiducials' reach (0.02 inset + 0.06 size) so patches never touch them.
    static let marginFraction = 0.1
    /// Black gap between patches, as a fraction of one patch side.
    static let gapFraction = 0.15
}

enum CalibrationTarget: Equatable, Codable {
    case chart(id: String)
    case flat(p3: [Double])

    private enum CodingKeys: String, CodingKey { case kind, id, p3 }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "chart": self = .chart(id: try c.decode(String.self, forKey: .id))
        case "flat": self = .flat(p3: try c.decode([Double].self, forKey: .p3))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown target \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .chart(let id):
            try c.encode("chart", forKey: .kind)
            try c.encode(id, forKey: .id)
        case .flat(let p3):
            try c.encode("flat", forKey: .kind)
            try c.encode(p3, forKey: .p3)
        }
    }
}

struct CalibrationDisplayInfo: Codable {
    var gamut = "P3"
    var brightnessLocked: Bool
    var trueTone: Bool?
    var nightShift: Bool?
    var widthPx: Int
    var heightPx: Int
}

struct CalibrationLayout: Codable {
    var rows: Int
    var columns: Int
    var marginFraction: Double
    var gapFraction: Double
    var fiducials = true
    var orientation: String
}

struct CalibrationPatch: Codable {
    var index: Int
    var name: String
    var row: Int
    var column: Int
    var p3: [Double]
    var lab: [Double]?
}

/// One JSON message; field names follow the protocol document. Unknown keys are ignored.
struct CalibrationEnvelope: Codable {
    var type: String
    var pv: Int?
    var app: String?
    var device: String?
    var display: CalibrationDisplayInfo?
    var charts: [String]?
    var seq: Int?
    var target: CalibrationTarget?
    var layout: CalibrationLayout?
    var patches: [CalibrationPatch]?
    var message: String?
}

/// What the calibration screen draws for the current target.
struct CalibrationFrame {
    var target: CalibrationTarget
    /// Grid as drawn (already turned to the screen's orientation); nil for a flat field.
    var chart: PatchChart?
    var flat: Vec3?
}

/// The Checker end of the link: advertises `bokki-calib`, accepts one BOKKI CAM at a time and answers
/// its requests by putting targets on screen.
@MainActor
@Observable
final class CalibrationLink: NSObject {
    enum State: Equatable { case waiting, connected(String), finished(String) }

    private(set) var state: State = .waiting
    private(set) var frame: CalibrationFrame?
    private(set) var lastError: String?
    /// Pairing code for this screen session, shown as a QR so a CAM can connect to this Checker only.
    let pairingCode: String = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })

    /// Opened by scanning the QR: launches BOKKI CAM straight into calibration with this Checker.
    var pairingURL: URL {
        var c = URLComponents()
        c.scheme = "bokkicam"
        c.host = "calibrate"
        c.queryItems = [URLQueryItem(name: "pv", value: String(CalibrationProtocol.version)),
                        URLQueryItem(name: "code", value: pairingCode),
                        URLQueryItem(name: "name", value: peer.displayName)]
        return c.url!
    }

    /// Set by the screen: resolves a chart id (built-in or custom) and the canvas orientation.
    var chartLookup: (String) -> PatchChart? = { _ in nil }
    var availableCharts: () -> [String] = { [] }
    /// Current drawing size in points, so `shown` can report the orientation the grid was drawn in.
    var canvasSize: CGSize = UIScreen.main.bounds.size

    @ObservationIgnored private let peer = MCPeerID(displayName: UIDevice.current.name)
    @ObservationIgnored private var session: MCSession!
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser!
    @ObservationIgnored private var camera: MCPeerID?
    @ObservationIgnored private var lastShown: (seq: Int, data: Data)?

    override init() {
        super.init()
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peer,
                                               discoveryInfo: ["app": "BOKKI Checker", "pv": String(CalibrationProtocol.version),
                                                               "code": pairingCode],
                                               serviceType: CalibrationProtocol.serviceType)
        advertiser.delegate = self
    }

    func start() {
        state = .waiting
        advertiser.startAdvertisingPeer()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
        camera = nil
        frame = nil
    }

    // MARK: Messages

    private func handle(_ data: Data, from peerID: MCPeerID) {
        guard let m = try? JSONDecoder().decode(CalibrationEnvelope.self, from: data) else {
            send(CalibrationEnvelope(type: "error", message: "unreadable message"), to: peerID)
            return
        }
        switch m.type {
        case "hello":
            guard m.pv == CalibrationProtocol.version else {
                send(CalibrationEnvelope(type: "error", message: "protocol version \(m.pv ?? 0) not supported"), to: peerID)
                return
            }
            state = .connected(m.device ?? peerID.displayName)
            let native = UIScreen.main.nativeBounds.size
            let display = CalibrationDisplayInfo(brightnessLocked: true, widthPx: Int(native.width), heightPx: Int(native.height))
            send(CalibrationEnvelope(type: "ready", pv: CalibrationProtocol.version, app: "BOKKI Checker",
                                     device: Self.modelIdentifier, display: display, charts: availableCharts()), to: peerID)
        case "show":
            guard let seq = m.seq, let target = m.target else {
                send(CalibrationEnvelope(type: "error", seq: m.seq, message: "show needs seq and target"), to: peerID)
                return
            }
            if let last = lastShown, last.seq == seq {
                try? session.send(last.data, toPeers: [peerID], with: .reliable)
                return
            }
            show(target, seq: seq, to: peerID)
        case "end":
            frame = nil
            if case .connected(let name) = state { state = .finished(name) }
        default:
            send(CalibrationEnvelope(type: "error", seq: m.seq, message: "unknown type \(m.type)"), to: peerID)
        }
    }

    private func show(_ target: CalibrationTarget, seq: Int, to peerID: MCPeerID) {
        let landscape = canvasSize.width > canvasSize.height
        switch target {
        case .flat(let p3):
            guard p3.count == 3 else {
                send(CalibrationEnvelope(type: "error", seq: seq, message: "flat needs three p3 values"), to: peerID)
                return
            }
            frame = CalibrationFrame(target: target, flat: Vec3(p3[0], p3[1], p3[2]))
            reply(CalibrationEnvelope(type: "shown", seq: seq, target: target, patches: []), seq: seq, to: peerID)
        case .chart(let id):
            guard let base = chartLookup(id), base.patches.count == base.rows * base.columns, base.layoutRects == nil else {
                send(CalibrationEnvelope(type: "error", seq: seq, message: "unknown chart \(id)"), to: peerID)
                return
            }
            // Fill the screen the long way: a landscape card on a portrait screen is turned 90°.
            let chart = base.isLandscape != landscape ? base.rotatedClockwise : base
            frame = CalibrationFrame(target: target, chart: chart)
            let patches = chart.patches.enumerated().map { i, p in
                let e = p.spec.encoded(in: .displayP3)
                let lab = p.spec.labD50
                return CalibrationPatch(index: i, name: p.name, row: i / chart.columns, column: i % chart.columns,
                                        p3: [e.x, e.y, e.z], lab: [lab.x, lab.y, lab.z])
            }
            let layout = CalibrationLayout(rows: chart.rows, columns: chart.columns,
                                           marginFraction: CalibrationProtocol.marginFraction,
                                           gapFraction: CalibrationProtocol.gapFraction,
                                           orientation: landscape ? "landscape" : "portrait")
            reply(CalibrationEnvelope(type: "shown", seq: seq, target: target, layout: layout, patches: patches), seq: seq, to: peerID)
        }
    }

    /// `shown` must follow the frame that contains the target, so wait a few display frames first.
    private func reply(_ message: CalibrationEnvelope, seq: Int, to peerID: MCPeerID) {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard let data = try? JSONEncoder().encode(message) else { return }
            lastShown = (seq, data)
            try? session.send(data, toPeers: [peerID], with: .reliable)
        }
    }

    private func send(_ message: CalibrationEnvelope, to peerID: MCPeerID) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        do { try session.send(data, toPeers: [peerID], with: .reliable) } catch { lastError = error.localizedDescription }
    }

    private static let modelIdentifier: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()

    // MARK: Delegate hops (MultipeerConnectivity calls back on its own queues)

    fileprivate func invited(by peerID: MCPeerID, handler: @escaping (Bool, MCSession?) -> Void) {
        // One camera at a time.
        guard camera == nil else { handler(false, nil); return }
        camera = peerID
        handler(true, session)
    }

    fileprivate func changed(_ peerID: MCPeerID, to state: MCSessionState) {
        guard peerID == camera, state == .notConnected else { return }
        camera = nil
        frame = nil
        lastShown = nil
        if case .connected = self.state { self.state = .waiting }
    }

    fileprivate func received(_ data: Data, from peerID: MCPeerID) {
        guard peerID == camera else { return }
        handle(data, from: peerID)
    }
}

extension CalibrationLink: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let handler = invitationHandler
        Task { @MainActor in self.invited(by: peerID, handler: handler) }
    }
}

extension CalibrationLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.changed(peerID, to: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.received(data, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
