// Pairing.swift — how the app learns where Home Assistant is without being told.
//
// The download button in the Home Assistant panel hands over a zip holding the app
// and one small file beside it. That file carries the address Home Assistant
// answers on and the key this Mac should use, which Home Assistant has already
// written down — so the app connects and is let straight in, with nothing typed
// and no Allow to press.
//
// The app itself is never touched, because changing anything inside a signed
// bundle stops macOS running it at all. The file sits next to the app instead,
// which is why it is looked for in the folder the app was opened from and in
// Downloads, where it will be if the app was dragged to Applications first.
//
// If it is not found, nothing is broken: the app looks for Home Assistant on the
// network instead and somebody presses Allow once. That is the fallback, not the
// plan.

import Foundation

enum Pairing {
    static let fileName = "ulanzi-deck-pairing.json"

    static func haveSettingsFile() -> Bool {
        FileManager.default.fileExists(atPath: settingsFile.path)
    }

    /// The pairing file, if Home Assistant sent one and it is still beside the app.
    static func findBesideTheApp() -> Settings? {
        guard !haveSettingsFile() else { return nil }      // already paired; leave it alone
        let fm = FileManager.default
        let beside = Bundle.main.bundleURL.deletingLastPathComponent()
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        for folder in [beside, downloads].compactMap({ $0 }) {
            let f = folder.appendingPathComponent(fileName)
            if let d = try? Data(contentsOf: f),
               let s = try? JSONDecoder().decode(Settings.self, from: d),
               !s.url.isEmpty, s.bridgeId.count >= 8, s.secret.count >= 16 {
                return s
            }
        }
        return nil
    }

    /// Save what Home Assistant sent as this Mac's settings, before anything connects.
    static func write(_ s: Settings) {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(s) else { return }
        try? d.write(to: settingsFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsFile.path)
    }
}

/// Finds Home Assistant on the network, so the address need not be typed.
/// Home Assistant announces itself as _home-assistant._tcp; this takes the first
/// one that answers and gives up after a few seconds.
final class HomeAssistantFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var done: ((String?) -> Void)?
    private var timeout: Timer?

    init(_ done: @escaping (String?) -> Void) {
        self.done = done
        super.init()
    }

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_home-assistant._tcp.", inDomain: "local.")
        timeout = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.finish(nil)
        }
    }

    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        services.append(s)
        s.delegate = self
        s.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ s: NetService) {
        // the TXT record carries the address Home Assistant wants to be reached on
        var url: String?
        if let txt = s.txtRecordData() {
            let d = NetService.dictionary(fromTXTRecord: txt)
            if let base = d["base_url"], let str = String(data: base, encoding: .utf8), !str.isEmpty {
                url = str
            }
        }
        if url == nil, let host = s.hostName {
            let h = host.hasSuffix(".") ? String(host.dropLast()) : host
            url = "http://\(h):\(s.port)"
        }
        finish(url)
    }

    func netService(_ s: NetService, didNotResolve error: [String: NSNumber]) {}

    private func finish(_ url: String?) {
        guard let done = done else { return }
        self.done = nil
        timeout?.invalidate()
        browser.stop()
        done(url)
    }
}
