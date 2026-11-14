// ulanzi-deck-bridge — the Mac end of the Ulanzi D200 Home Assistant Control Deck.
//
// The deck has no network. This holds its USB link and carries messages between
// it and Home Assistant, and it is deliberately dumb about what the messages
// mean: Home Assistant draws the keys and decides what a press does, the deck
// shows them, and this passes bytes. The two things it does for itself are the
// two the deck cannot: tell it the time, and tell it whether anyone is listening.
//
//   deck  <— 1024-byte HID reports —>  bridge  <— WebSocket —>  Home Assistant
//
// No drivers, no dependencies, no access token: on first contact Home Assistant
// shows "a bridge wants to connect" in the Ulanzi Deck panel, and one click on
// Allow pairs it for good.

import Foundation
import IOKit
import IOKit.hid
import CoreText
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)

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

// ------------------------------------------------------------------ putting them together

let args = Array(CommandLine.arguments.dropFirst())
func value(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
if args.contains("--help") || args.contains("-h") {
    print("""
    ulanzi-deck-bridge \(bridgeVersion)

      ulanzi-deck-bridge [--url http://homeassistant.local:8123]
          Run the bridge. --url is remembered, so it is only needed once.
      ulanzi-deck-bridge --set-url http://homeassistant.local:8123
          Remember where Home Assistant is, and exit.
      ulanzi-deck-bridge --grid
          Find where the keys are: nudge lines onto their edges with arrow keys
          shown on the deck, one line at a time. The positions are saved.
      ulanzi-deck-bridge --keytest
          Learn which physical key is which: press all fourteen in order.
      ulanzi-deck-bridge --push layout.bin
          Send a layout file straight to the deck (for development).
    """)
    exit(0)
}

let deck = Deck()
let dateFormat: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEEdMMM")
    return f
}()

var haUp = false
var lastStatus = Date.distantPast
var statusBody = Data()
var deckAlive: Bool { deck.attached && Date().timeIntervalSince(lastStatus) < 6 }

/// The heartbeat. Carries everything the deck cannot know by itself.
func ping() {
    guard deck.attached else { return }
    var m = Data([1])
    var now = UInt32(Date().timeIntervalSince1970).littleEndian
    var tz = Int32(TimeZone.current.secondsFromGMT()).littleEndian
    withUnsafeBytes(of: &now) { m.append(contentsOf: $0) }
    withUnsafeBytes(of: &tz) { m.append(contentsOf: $0) }
    let date = Array(dateFormat.string(from: Date()).utf8.prefix(48))
    m.append(haUp ? 1 : 0)
    m.append(UInt8(date.count))
    m.append(contentsOf: date)
    deck.send(m)
}

// --- one-off modes ---------------------------------------------------------

if let file = value(after: "--push") {
    guard let blob = try? Data(contentsOf: URL(fileURLWithPath: file)) else { print("cannot read \(file)"); exit(1) }
    var sent = false
    let started = Date()
    deck.onMessage = { m in
        guard m.first == 0x81, m.count >= 11 else { return }
        let id = m.subdata(in: 7..<11).map { String(format: "%02x", $0) }.reversed().joined()
        if !sent {
            sent = true
            print("deck answered; firmware \(m[2]).\(m[3]), layout \(id). Sending \(blob.count) bytes…")
            let t = Date()
            deck.send(Data([2]) + blob) { ok in
                print(ok ? String(format: "sent in %.2f s", Date().timeIntervalSince(t)) : "send failed")
                if !ok { exit(1) }
            }
        } else {
            print("deck now reports layout \(id), \(m[5]) screen(s)")
            exit(0)
        }
    }
    deck.onAttach = { ping() }
    deck.start()
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        if !sent { ping() }
        if Date().timeIntervalSince(started) > 20 { print("no answer from the deck"); exit(1) }
    }
    RunLoop.main.run()
}

if args.contains("--keytest") {
    var codes: [UInt8] = []
    print("Press every key once, in reading order: top row left to right, then the middle row,")
    print("then the bottom row, finishing with the wide key. Waiting for the deck…")
    deck.onMessage = { m in
        if m.first == 0x81 && lastStatus == Date.distantPast { lastStatus = Date(); print("Deck is listening. Go ahead.") }
        guard m.first == 0x83, m.count >= 3, m[2] == 1 else { return }
        let code = m[1]
        if codes.contains(code) { print("  (key code \(code) again — ignored)"); return }
        codes.append(code)
        print("  key \(codes.count) of 14: code \(code)")
        if codes.count == 14 {
            deck.send(Data([7] + codes)) { ok in
                print(ok ? "Saved on the deck: \(codes.map(String.init).joined(separator: ","))" : "could not save")
                exit(ok ? 0 : 1)
            }
        }
    }
    deck.onAttach = { ping() }
    deck.start()
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in ping() }
    RunLoop.main.run()
}

// --- finding where the keys are --------------------------------------------
//
// The deck's screen is one panel behind fourteen windows in the case, and
// nothing in software says where the windows are. So the person looking at the
// deck draws them: one line at a time, nudged onto an edge with arrow keys that
// are labelled on the deck itself, then Next line. Lines already placed stay
// on screen, so the grid builds up in front of them. Two upright and two level
// lines round each key give its rectangle; the positions are saved to a file.
//
// Run with the login agent stopped, so nothing else draws.

if args.contains("--grid") {
    struct Rect { var x: Int, y: Int, w: Int, h: Int }
    struct Line { let name: String; let upright: Bool; var at: Int; let from: Int; let to: Int }
    let gridFile = supportDir.appendingPathComponent("grid.json")

    // the screen cut into fourteen tiles that cover all of it, so a line can go anywhere
    let tiles: [Rect] = (0..<13).map { Rect(x: ($0 % 5) * 256, y: ($0 / 5) * 240, w: 256, h: 240) } + [Rect(x: 768, y: 480, w: 512, h: 240)]

    // where the edges are thought to be. Only starting points: each line starts a
    // little inside its key, where it can be seen, to be nudged out to the edge.
    let colX = [14, 271, 530, 789, 1049], rowY = [3, 262, 521], size = 196, wideX = 782, wideW = 458, inset = 10
    let split = 490     // below this is the bottom row, where the last two columns give way to the wide key
    var lines: [Line] = []
    for c in 0..<5 {
        let to = c < 3 ? 720 : split
        lines.append(Line(name: "column \(c + 1) left", upright: true, at: colX[c] + inset, from: 0, to: to))
        lines.append(Line(name: "column \(c + 1) right", upright: true, at: colX[c] + size - 1 - inset, from: 0, to: to))
    }
    lines.append(Line(name: "wide key left", upright: true, at: wideX + inset, from: split, to: 720))
    lines.append(Line(name: "wide key right", upright: true, at: wideX + wideW - 1 - inset, from: split, to: 720))
    for r in 0..<3 {
        lines.append(Line(name: "row \(r + 1) top", upright: false, at: rowY[r] + inset, from: 0, to: 1280))
        lines.append(Line(name: "row \(r + 1) bottom", upright: false, at: rowY[r] + size - 1 - inset, from: 0, to: 1280))
    }
    var current = 0     // the line being placed; == lines.count when all are
    var redo = false    // --only "name": every line is already placed and one is being put right

    // --only "row 2 top" picks up the saved grid and lets that one line be placed again
    if let name = value(after: "--only"),
       let d = try? Data(contentsOf: gridFile),
       let saved = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
       let rows = saved["lines"] as? [[String: Any]] {
        for row in rows {
            if let n = row["name"] as? String, let at = row["at"] as? Int, let i = lines.firstIndex(where: { $0.name == n }) {
                lines[i].at = at
            }
        }
        guard let i = lines.firstIndex(where: { $0.name == name }) else { print("no line called \(name)"); exit(1) }
        current = i; redo = true
    }

    // words for the keys that do something, drawn where those keys are thought to be
    func word(_ text: String, _ points: CGFloat) -> (w: Int, h: Int, a: [UInt8]) {
        let font = CTFontCreateWithName("Helvetica Neue Medium" as CFString, points, nil)
        let str = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])
        let line = CTLineCreateWithAttributedString(str)
        let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let w = Int(ceil(b.width)) + 4, h = Int(ceil(b.height)) + 4
        var a = [UInt8](repeating: 0, count: w * h)
        a.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.textPosition = CGPoint(x: 2 - b.minX, y: 2 - b.minY)
            CTLineDraw(line, ctx)
        }
        return (w, h, a)
    }
    let labels: [(String, Int, Int)] = [("Up", 369, 360), ("Left", 112, 619), ("Down", 369, 619), ("Right", 628, 619)]
    let labelArt = labels.map { word($0.0, 40) }

    func picture(_ t: Rect) -> Data {
        var px = [UInt32](repeating: 0, count: t.w * t.h)
        func put(_ x: Int, _ y: Int, _ c: UInt32) { if x >= t.x, x < t.x + t.w, y >= t.y, y < t.y + t.h { px[(y - t.y) * t.w + x - t.x] = c } }
        func stamp(_ art: (w: Int, h: Int, a: [UInt8]), _ cx: Int, _ cy: Int) {
            for y in 0..<art.h { for x in 0..<art.w where art.a[y * art.w + x] > 0 {
                let v = UInt32(art.a[y * art.w + x]); put(cx - art.w / 2 + x, cy - art.h / 2 + y, v << 16 | v << 8 | v)
            } }
        }
        for (i, l) in labels.enumerated() { stamp(labelArt[i], l.1, l.2) }
        if current < lines.count {
            stamp(word(redo ? "Done" : "Next line", 40), 1011, redo ? 619 : 606)
            if !redo { stamp(word("\(current + 1) of \(lines.count)", 24), 1011, 652) }
        } else {
            stamp(word("All done", 40), 1011, 619)
        }
        for (i, l) in lines.enumerated() where redo || i <= current {      // placed lines green, the one being placed white, on top
            let c: UInt32 = i == current ? 0xFFFFFF : 0x00C853
            for p in l.from..<l.to { if l.upright { put(l.at, p, c) } else { put(p, l.at, c) } }
        }
        if current < lines.count {
            let l = lines[current]
            for p in l.from..<l.to { if l.upright { put(l.at, p, 0xFFFFFF) } else { put(p, l.at, 0xFFFFFF) } }
        }
        var d = Data([UInt8(t.w & 255), UInt8(t.w >> 8), UInt8(t.h & 255), UInt8(t.h >> 8)])
        var a = 0
        while a < px.count {
            var b = a + 1
            while b < px.count && px[b] == px[a] && b - a < 65535 { b += 1 }
            let n = b - a
            if n <= 128 { d.append(UInt8(n - 1)) } else { d.append(0xFF); d.append(UInt8(n & 255)); d.append(UInt8(n >> 8)) }
            d.append(contentsOf: [UInt8(px[a] >> 16 & 255), UInt8(px[a] >> 8 & 255), UInt8(px[a] & 255)])
            a = b
        }
        return d
    }
    func u32(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }
    func u16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }
    func layout() -> Data {     // the first picture of every tile, as a layout the deck will accept
        let pics = tiles.map { picture($0) }
        let head = 24 + 8 * 14
        var pos = head + 32 * 14
        var table = Data(), body = Data()
        for p in pics {
            var rec = [UInt8](repeating: 0, count: 32)
            rec[4] = 1
            rec.replaceSubrange(24..<28, with: u32(pos)); rec.replaceSubrange(28..<32, with: u32(p.count))
            table.append(contentsOf: rec); body.append(p); pos += p.count
        }
        var out = Data("UDL2".utf8)
        // header: size, a random id, 1 screen, 0 fonts, start on screen 0, and 0 for
        // the screen-off timeout — the deck must not go dark part way through a measurement
        out.append(contentsOf: u32(pos) + u32(Int.random(in: 1..<0x7FFFFFFF)) + [1, 0, 0, 0] + u32(head) + u32(head))
        for t in tiles { out.append(contentsOf: u16(t.x) + u16(t.y) + u16(t.w) + u16(t.h)) }
        return out + table + body
    }

    var sent = [Data?](repeating: nil, count: 14)
    func draw() {
        for (n, t) in tiles.enumerated() {
            let pic = picture(t)
            if sent[n] != pic { sent[n] = pic; deck.send(Data([3, 0, UInt8(n)]) + pic) }
        }
    }
    func save() {
        let rows: [[String: Any]] = lines.enumerated().map { ["name": $1.name, "at": $1.at, "placed": redo || $0 < current] }
        let placed = redo ? lines.count : current
        if let d = try? JSONSerialization.data(withJSONObject: ["placed": placed, "of": lines.count, "lines": rows, "replacing": redo && current < lines.count], options: [.prettyPrinted]) {
            try? d.write(to: gridFile, options: .atomic)
        }
    }

    // Up, Left, Down, Right and Next line, by where they are on the deck (0 is top-left, reading order)
    var keymapNow: [UInt8] = [], started = false, held = 0, heldSince = Date()
    func nudge(_ by: Int) {
        guard current < lines.count else { return }
        let limit = lines[current].upright ? 1279 : 719
        let to = max(0, min(limit, lines[current].at + by))
        if to != lines[current].at { lines[current].at = to; draw() }
    }
    deck.onMessage = { m in
        if m.first == 0x81, m.count >= 25 {
            keymapNow = Array(m[11..<25])
            if !started { started = true; save(); deck.send(Data([2]) + layout()) { _ in draw() } }
            return
        }
        guard started, m.first == 0x83, m.count >= 3, let pos = keymapNow.firstIndex(of: m[1]) else { return }
        if m[2] == 0 { held = 0; return }
        guard current < lines.count else { return }
        let upright = lines[current].upright
        switch pos {
        case 10 where upright: held = -1      // Left
        case 12 where upright: held = 1       // Right
        case 6 where !upright: held = -1      // Up
        case 11 where !upright: held = 1      // Down
        case 13:                              // Next line
            current = redo ? lines.count : current + 1; held = 0; save(); draw()
            print(current < lines.count ? "placing: \(lines[current].name)" : "all lines placed")
            return
        default: held = 0; return
        }
        heldSince = Date(); nudge(held)
    }
    func gridPing() {       // says Home Assistant is up, so the deck draws no warning dot
        guard deck.attached else { return }
        var m = Data([1])
        var now = UInt32(Date().timeIntervalSince1970).littleEndian, tz = Int32(TimeZone.current.secondsFromGMT()).littleEndian
        withUnsafeBytes(of: &now) { m.append(contentsOf: $0) }
        withUnsafeBytes(of: &tz) { m.append(contentsOf: $0) }
        m.append(1); m.append(0)
        deck.send(m)
    }
    deck.onAttach = { gridPing() }
    deck.start()
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in gridPing() }
    // holding an arrow keeps the line moving: slowly at first, then faster
    Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
        let t = Date().timeIntervalSince(heldSince)
        if held != 0 && t > 0.4 { nudge(held * (t > 1.5 ? 3 : 1)) }
    }
    RunLoop.main.run()
}

if let url = value(after: "--set-url") {
    let s = loadSettings(url: url)
    print("Home Assistant is at \(s.url)")
    exit(0)
}

// --- the bridge proper -----------------------------------------------------

let settings = loadSettings(url: value(after: "--url"))
let link = Link(settings: settings)
var announced = false       // Home Assistant has been told a deck is here

func reconcile() {
    let should = link.ready && deckAlive
    if should && !announced {
        announced = true
        link.sendJSON(["type": "deck", "status": statusBody.base64EncodedString()])
        log("deck online")
    } else if !should && announced {
        announced = false
        if link.ready { link.sendJSON(["type": "deck_gone"]) }
        log("deck offline")
    }
    let up = link.ready
    if up != haUp { haUp = up; ping() }
}

deck.onMessage = { m in
    switch m.first {
    case 0x81:                                  // STATUS: screen, layout, firmware
        lastStatus = Date()
        let body = m.dropFirst()
        if Data(body) != statusBody {
            statusBody = Data(body)
            if announced { link.sendDeckMessage(m) }
        }
        reconcile()
    case 0x82:                                  // a key was tapped or held
        if announced { link.sendDeckMessage(m) }
    default:
        break
    }
}
deck.onAttach = { ping() }
deck.onDetach = { lastStatus = .distantPast; statusBody = Data(); reconcile() }
link.onReady = { reconcile() }
link.onDown = { reconcile() }
link.onDeckMessage = { m in if deck.attached { deck.send(m) } }

log("ulanzi-deck-bridge \(bridgeVersion); Home Assistant at \(settings.url)")
deck.start()
link.connect()
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    ping()
    reconcile()
}
RunLoop.main.run()
