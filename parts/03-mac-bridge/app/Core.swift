// Core.swift — the parts of the bridge that are the same whether it runs as a
// background agent or inside the Mac app: the settings file, the deck's USB link
// and the WebSocket to Home Assistant. Lifted unchanged from main.swift, which is
// still the command-line build used for the developer tools.
import Foundation
import IOKit
import IOKit.hid
import CoreText
import CoreGraphics


let bridgeVersion = "1.0"
let stamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()
func log(_ s: String) { print("\(stamp.string(from: Date())) \(s)") }

// ------------------------------------------------------------------ settings

struct Settings: Codable {
    var url: String
    var bridgeId: String
    var secret: String
}

let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/UlanziDeck")
let settingsFile = supportDir.appendingPathComponent("bridge.json")

func randomHex(_ n: Int) -> String {
    var b = [UInt8](repeating: 0, count: n)
    _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
    return b.map { String(format: "%02x", $0) }.joined()
}

func loadSettings(url override: String?) -> Settings {
    var s: Settings
    if let d = try? Data(contentsOf: settingsFile), let got = try? JSONDecoder().decode(Settings.self, from: d) {
        s = got
    } else {
        s = Settings(url: "http://homeassistant.local:8123", bridgeId: UUID().uuidString.lowercased(), secret: randomHex(32))
    }
    if let o = override { s.url = o }
    try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let d = try? enc.encode(s) {
        try? d.write(to: settingsFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsFile.path)
    }
    return s
}

// ------------------------------------------------------------------ the deck, over HID

final class Deck {
    static let reportSize = 1024
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private let inBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: Deck.reportSize)
    private let outQueue = DispatchQueue(label: "ulanzi-deck.out")
    private var rx = Data()
    private var rxLive = false

    var onMessage: ((Data) -> Void)?
    var onAttach: (() -> Void)?
    var onDetach: (() -> Void)?
    var attached: Bool { device != nil }

    func start() {
        // The data channel is the gadget's vendor interface. It describes itself
        // as a Consumer Control with 1024-byte reports; the 8-byte boot keyboard
        // beside it is the other interface and is left alone.
        let match: [String: Any] = [
            kIOHIDVendorIDKey: 0x2207,
            kIOHIDProductIDKey: 0x0019,
            kIOHIDDeviceUsagePageKey: 0x0C,
            kIOHIDDeviceUsageKey: 0x01,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<Deck>.fromOpaque(ctx!).takeUnretainedValue().found(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<Deck>.fromOpaque(ctx!).takeUnretainedValue().lost(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess { log("HID manager would not open (\(String(format: "0x%08x", r)))") }
    }

    private func found(_ dev: IOHIDDevice) {
        let size = (IOHIDDeviceGetProperty(dev, kIOHIDMaxOutputReportSizeKey as CFString) as? Int) ?? 0
        guard size == Deck.reportSize, device == nil else { return }
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            log("deck found but would not open (\(String(format: "0x%08x", r)))")
            return
        }
        device = dev
        rxLive = false
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inBuf, Deck.reportSize, { ctx, _, _, _, _, report, length in
            Unmanaged<Deck>.fromOpaque(ctx!).takeUnretainedValue().report(report, length)
        }, ctx)
        log("deck attached")
        onAttach?()
    }

    private func lost(_ dev: IOHIDDevice) {
        guard let d = device, d == dev else { return }
        device = nil
        log("deck detached")
        onDetach?()
    }

    // A report is: flags (1 first, 2 last), u16 payload length, payload.
    private func report(_ p: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard length >= 3 else { return }
        let flags = p[0]
        let n = min(Int(p[1]) | Int(p[2]) << 8, length - 3)
        if flags & 1 != 0 { rx.removeAll(keepingCapacity: true); rxLive = true }
        guard rxLive else { return }
        rx.append(UnsafeBufferPointer(start: p + 3, count: n))
        if flags & 2 != 0 {
            rxLive = false
            let msg = rx
            if !msg.isEmpty { onMessage?(msg) }
        }
    }

    /// Queue one whole message for the deck. Order is kept; nothing blocks the caller.
    func send(_ msg: Data, then done: ((Bool) -> Void)? = nil) {
        guard let dev = device else { done?(false); return }
        outQueue.async {
            var ok = true
            var rep = [UInt8](repeating: 0, count: Deck.reportSize)
            let room = Deck.reportSize - 3
            var off = 0
            repeat {
                let n = min(room, msg.count - off)
                rep[0] = (off == 0 ? 1 : 0) | (off + n >= msg.count ? 2 : 0)
                rep[1] = UInt8(n & 0xFF)
                rep[2] = UInt8(n >> 8)
                msg.copyBytes(to: &rep[3], from: off..<(off + n))
                if n < room { for i in (3 + n)..<Deck.reportSize { rep[i] = 0 } }
                if IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, rep, Deck.reportSize) != kIOReturnSuccess {
                    ok = false
                    break
                }
                off += n
            } while off < msg.count
            if let done = done { DispatchQueue.main.async { done(ok) } }
        }
    }
}

// ------------------------------------------------------------------ Home Assistant, over a WebSocket

final class Link: NSObject, URLSessionWebSocketDelegate {
    private let settings: Settings
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var pinger: Timer?
    private(set) var ready = false          // paired, and Home Assistant is listening
    private var saidPending = false
    private var failures = 0                // consecutive, for backing off

    var onReady: (() -> Void)?
    var onDown: (() -> Void)?
    var onDeckMessage: ((Data) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        super.init()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }

    func connect() {
        var base = settings.url
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasPrefix("https://") { base = "wss://" + base.dropFirst(8) }
        else if base.hasPrefix("http://") { base = "ws://" + base.dropFirst(7) }
        guard let url = URL(string: base + "/api/ulanzi_deck/bridge") else {
            log("the Home Assistant address is not a URL: \(settings.url)")
            return
        }
        let t = session.webSocketTask(with: url)
        t.maximumMessageSize = 32 << 20
        task = t
        t.resume()
        receive(t)
    }

    private func drop(_ why: String) {
        guard task != nil else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        pinger?.invalidate()
        if ready { log("Home Assistant link lost: \(why)") }
        ready = false
        onDown?()
        failures += 1
        let wait = min(30.0, 3.0 * Double(failures))     // 3 s, 6 s … 30 s
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.connect() }
    }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
        guard t === task else { return }
        let host = Host.current().localizedName ?? "Mac"
        sendJSON(["type": "hello", "bridge_id": settings.bridgeId, "secret": settings.secret,
                  "name": host, "version": bridgeVersion])
        pinger = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self = self, let t = self.task else { return }
            t.sendPing { err in
                if err != nil { DispatchQueue.main.async { self.drop("no answer to a ping") } }
            }
        }
    }

    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) {
        guard t === task else { return }
        drop(error?.localizedDescription ?? "closed")
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, t === self.task else { return }
                switch result {
                case .failure(let e):
                    self.drop(e.localizedDescription)
                case .success(.data(let d)):
                    self.onDeckMessage?(d)          // binary frames are for the deck, untouched
                    self.receive(t)
                case .success(.string(let s)):
                    self.control(s)
                    self.receive(t)
                case .success:
                    self.receive(t)
                }
            }
        }
    }

    private func control(_ s: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "pending":
            if !saidPending {
                log("waiting to be allowed: open the Ulanzi Deck panel in Home Assistant and press Allow")
                saidPending = true
            }
        case "ready":
            failures = 0
            log("Home Assistant connected")
            ready = true
            saidPending = false
            onReady?()
        default:
            break
        }
    }

    func sendJSON(_ obj: [String: Any]) {
        guard let t = task, let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        t.send(.string(s)) { _ in }
    }

    func sendDeckMessage(_ d: Data) {
        task?.send(.data(d)) { _ in }
    }
}
