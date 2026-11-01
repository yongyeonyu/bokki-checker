import Foundation
import Observation
import os
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

/// Where a `show` sits in the CAM's run; only used to show progress. Fields optional so a partial
/// `step` never makes a message unreadable.
struct CalibrationStep: Codable, Equatable {
    var index: Int?
    var total: Int?
    var label: String?
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
    var features: [String]?
    var seq: Int?
    var ok: Bool?
    var step: CalibrationStep?
    var target: CalibrationTarget?
    var layout: CalibrationLayout?
    var patches: [CalibrationPatch]?
    var message: String?
}

/// Just enough of a message to ack a `captured` whose other fields did not decode.
private struct MessageHead: Decodable {
    var type: String
    var seq: Int?
}

/// What the calibration screen draws for the current target.
struct CalibrationFrame {
    var target: CalibrationTarget
    /// Grid as drawn (already turned to the screen's orientation); nil for a flat field.
    var chart: PatchChart?
    var flat: Vec3?
    /// The CAM's progress for this round, shown in the chart's black margin (never on flats).
    var step: CalibrationStep?
}

/// The Checker end of the link: advertises `bokki-calib`, accepts one BOKKI CAM at a time and answers
/// its requests by putting targets on screen.
@MainActor
@Observable
final class CalibrationLink: NSObject {
    /// `reconnecting`: the camera dropped mid-run; the token, target and step stay up while it rejoins.
    enum State: Equatable { case waiting, connected(String), reconnecting(String) }

    /// How long a dropped camera has to rejoin before the screen goes back to a new QR.
    static let rejoinWindow: Duration = .seconds(30)
    /// No message from a connected camera for this long while a target is up: it has stopped or hung
    /// (its own timeouts are 5 s at most), so the screen offers a way out instead of a silent target.
    static let stallWindow: Duration = .seconds(15)

    private(set) var state: State = .waiting
    private(set) var frame: CalibrationFrame?
    private(set) var lastError: String?
    /// A target is up but the camera has gone quiet (see `stallWindow`).
    private(set) var stalled = false
    /// Camera that finished the last run (after `end`), shown on the waiting screen.
    private(set) var lastFinished: String?
    /// Fresh for every waiting screen; advertised in the discovery info and shown as a QR so a CAM
    /// connects to this Checker only.
    private(set) var token = CalibrationLink.makeToken()

    /// QR payload (protocol: `bokkicalib://connect?pv=1&token=<token>`), read by BOKKI CAM's Photo preview.
    var pairingPayload: String { "bokkicalib://connect?pv=\(CalibrationProtocol.version)&token=\(token)" }

    /// Set by the screen: resolves a chart id (built-in or custom) and the canvas orientation.
    var chartLookup: (String) -> PatchChart? = { _ in nil }
    var availableCharts: () -> [String] = { [] }
    /// Current drawing size in points, so `shown` can report the orientation the grid was drawn in.
    var canvasSize: CGSize = UIScreen.main.bounds.size

    @ObservationIgnored private let peer = MCPeerID(displayName: UIDevice.current.name)
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var camera: MCPeerID?
    @ObservationIgnored private var lastShown: (seq: Int, data: Data)?
    @ObservationIgnored private var rejoinTimeout: Task<Void, Never>?
    @ObservationIgnored private var stallWatch: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.bokki.checker", category: "calibration")

    func start() {
        lastFinished = nil
        beginWaiting()
    }

    /// Drops the current camera and target and shows a fresh QR.
    func restart() {
        log.info("restart by user")
        start()
    }

    func stop() {
        tearDown()
        state = .waiting
    }

    /// Back in the foreground: iOS stops advertising in the background, so advertise again (same token).
    func resume() {
        log.info("foreground: advertising again, camera \(self.camera?.displayName ?? "none", privacy: .public)")
        advertiser?.startAdvertisingPeer()
    }

    /// New token, new session and a new advertiser carrying that token; the old camera (if any) is dropped.
    private func beginWaiting() {
        tearDown()
        token = Self.makeToken()
        state = .waiting
        log.info("waiting with token \(self.token, privacy: .public)")
        replaceSession()
        let advertiser = MCNearbyServiceAdvertiser(peer: peer,
                                                   discoveryInfo: ["app": "BOKKI Checker", "pv": String(CalibrationProtocol.version),
                                                                   "token": token],
                                                   serviceType: CalibrationProtocol.serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
    }

    /// A fresh session for the next (or returning) camera; the old one is dropped without callbacks.
    private func replaceSession() {
        session?.delegate = nil
        session?.disconnect()
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        camera = nil
    }

    private func tearDown() {
        rejoinTimeout?.cancel()
        rejoinTimeout = nil
        stallWatch?.cancel()
        stallWatch = nil
        stalled = false
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        session?.delegate = nil
        session?.disconnect()
        session = nil
        camera = nil
        frame = nil
        lastShown = nil
    }

    private static func makeToken() -> String {
        String((0..<10).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
    }

    // MARK: Messages

    private func handle(_ data: Data, from peerID: MCPeerID) {
        guard let m = try? JSONDecoder().decode(CalibrationEnvelope.self, from: data) else {
            // `captured` is never answered with an error: ack it even if some other field is malformed.
            if let head = try? JSONDecoder().decode(MessageHead.self, from: data), head.type == "captured", let seq = head.seq {
                send(CalibrationEnvelope(type: "ack", seq: seq), to: peerID)
            } else {
                send(CalibrationEnvelope(type: "error", message: "unreadable message"), to: peerID)
            }
            return
        }
        switch m.type {
        case "hello":
            guard m.pv == CalibrationProtocol.version else {
                send(CalibrationEnvelope(type: "error", message: "protocol version \(m.pv ?? 0) not supported"), to: peerID)
                return
            }
            // A second `hello` mid-run is a rejoin: answer `ready` again and keep the target on screen.
            rejoinTimeout?.cancel()
            rejoinTimeout = nil
            log.info("hello from \(peerID.displayName, privacy: .public), rejoin \(self.frame != nil)")
            // After a rejoin the repeated `show` is drawn again, so `shown` waits for a clean frame.
            lastShown = nil
            state = .connected(m.device ?? peerID.displayName)
            let native = UIScreen.main.nativeBounds.size
            let display = CalibrationDisplayInfo(brightnessLocked: true, widthPx: Int(native.width), heightPx: Int(native.height))
            send(CalibrationEnvelope(type: "ready", pv: CalibrationProtocol.version, app: "BOKKI Checker",
                                     device: Self.modelIdentifier, display: display, charts: availableCharts(),
                                     features: ["handshake"]), to: peerID)
        case "show":
            guard let seq = m.seq, let target = m.target else {
                send(CalibrationEnvelope(type: "error", seq: m.seq, message: "show needs seq and target"), to: peerID)
                return
            }
            if let last = lastShown, last.seq == seq {
                log.info("show \(seq) again: resending shown")
                try? session?.send(last.data, toPeers: [peerID], with: .reliable)
                return
            }
            show(target, seq: seq, step: m.step, to: peerID)
        case "captured":
            // Handshake: the CAM has its shot. The target stays up until the next `show`.
            guard let seq = m.seq else { return }
            log.debug("captured \(seq): ack")
            send(CalibrationEnvelope(type: "ack", seq: seq), to: peerID)
        case "end":
            log.info("end")
            if case .connected(let name) = state { lastFinished = name }
            beginWaiting()
        default:
            send(CalibrationEnvelope(type: "error", seq: m.seq, message: "unknown type \(m.type)"), to: peerID)
        }
    }

    private func show(_ target: CalibrationTarget, seq: Int, step: CalibrationStep?, to peerID: MCPeerID) {
        let landscape = canvasSize.width > canvasSize.height
        switch target {
        case .flat(let p3):
            guard p3.count == 3, p3.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                send(CalibrationEnvelope(type: "error", seq: seq, message: "flat needs three p3 values in 0...1"), to: peerID)
                return
            }
            // Drawn exactly as sent: Display P3 gamma-encoded, no tone mapping or user tuning.
            frame = CalibrationFrame(target: target, flat: Vec3(p3[0], p3[1], p3[2]), step: step)
            reply(CalibrationEnvelope(type: "shown", seq: seq, target: target, patches: []), seq: seq, to: peerID)
        case .chart(let id):
            guard let base = chartLookup(id), base.patches.count == base.rows * base.columns, base.layoutRects == nil else {
                send(CalibrationEnvelope(type: "error", seq: seq, message: "unknown chart \(id)"), to: peerID)
                return
            }
            // Fill the screen the long way: a landscape card on a portrait screen is turned 90°.
            let chart = base.isLandscape != landscape ? base.rotatedClockwise : base
            frame = CalibrationFrame(target: target, chart: chart, step: step)
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
            guard peerID == camera, let data = try? JSONEncoder().encode(message) else { return }
            lastShown = (seq, data)
            try? session?.send(data, toPeers: [peerID], with: .reliable)
        }
    }

    private func send(_ message: CalibrationEnvelope, to peerID: MCPeerID) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        do { try session?.send(data, toPeers: [peerID], with: .reliable) } catch { lastError = error.localizedDescription }
    }

    private static let modelIdentifier: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()

    // MARK: Delegate hops (MultipeerConnectivity calls back on its own queues)

    fileprivate func invited(by peerID: MCPeerID, via advertiser: MCNearbyServiceAdvertiser,
                             handler: @escaping (Bool, MCSession?) -> Void) {
        // One camera at a time, and only through the advertiser carrying the current token.
        guard advertiser === self.advertiser else { handler(false, nil); return }
        if let camera {
            let stillConnecting = camera == peerID && session?.connectedPeers.contains(peerID) != true
            guard camera.displayName == peerID.displayName, !stillConnecting else {
                // Another camera, or a repeat invitation while the first is connecting (that would drop both).
                log.info("invite from \(peerID.displayName, privacy: .public) declined: busy")
                handler(false, nil); return
            }
            // The same phone inviting again before its drop reached us: it is rejoining, so give it a fresh session.
            log.info("invite from \(peerID.displayName, privacy: .public) while connected: rejoin, replacing session")
            replaceSession()
        }
        guard let session else { handler(false, nil); return }
        log.info("invite from \(peerID.displayName, privacy: .public) accepted")
        camera = peerID
        handler(true, session)
    }

    fileprivate func changed(_ peerID: MCPeerID, in session: MCSession, to state: MCSessionState) {
        guard session === self.session, peerID == camera else { return }
        log.info("\(peerID.displayName, privacy: .public) -> \(String(describing: state), privacy: .public)")
        guard state == .notConnected else { return }
        // Keep the token and keep advertising so the camera can rejoin; a fresh session takes it.
        replaceSession()
        advertiser?.startAdvertisingPeer()
        guard case .connected(let name) = self.state else { return }  // dropped before `hello`
        // Dropped mid-run: target and step stay up; a new QR only if it does not come back in time.
        self.state = .reconnecting(name)
        rejoinTimeout?.cancel()
        rejoinTimeout = Task { [weak self] in
            try? await Task.sleep(for: CalibrationLink.rejoinWindow)
            guard let self, !Task.isCancelled, case .reconnecting = self.state else { return }
            self.log.info("no rejoin: back to waiting")
            self.beginWaiting()
        }
    }

    fileprivate func received(_ data: Data, in session: MCSession, from peerID: MCPeerID) {
        guard session === self.session, peerID == camera else { return }
        handle(data, from: peerID)
        watchForStall()
    }

    private func watchForStall() {
        stalled = false
        stallWatch?.cancel()
        stallWatch = Task { [weak self] in
            try? await Task.sleep(for: CalibrationLink.stallWindow)
            guard let self, !Task.isCancelled, self.frame != nil else { return }
            self.log.info("camera quiet for \(CalibrationLink.stallWindow, privacy: .public)")
            self.stalled = true
        }
    }
}

extension CalibrationLink: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let handler = invitationHandler
        Task { @MainActor in self.invited(by: peerID, via: advertiser, handler: handler) }
    }
}

extension CalibrationLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.changed(peerID, in: session, to: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.received(data, in: session, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
