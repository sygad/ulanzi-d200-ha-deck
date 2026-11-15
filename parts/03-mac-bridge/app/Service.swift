// Service.swift — everything the app does, with no interface attached to it.
//
// One object holds the state the window draws: where Home Assistant is, whether
// it is listening, whether the deck is plugged in, and whether the deck is
// running our app or still the one it came with. The window only reads this and
// presses the three buttons at the bottom.

import Foundation
import ServiceManagement

@MainActor
final class Service: ObservableObject {

    /// What the app should be telling the user to do, in order.
    enum Step: Equatable {
        case findingHomeAssistant        // looking for it on the network
        case noHomeAssistant             // give up, ask for the address
        case waitingToBeAllowed          // Home Assistant has it, somebody must press Allow
        case noDeck                      // nothing plugged in
        case checkingDeck                // plugged in, working out what it is running
        case deckNeedsSettingUp          // plugged in, still running the app it came with
        case settingUpDeck(String)       // doing it, with a line to show
        case ready                       // all of it working
    }

    @Published private(set) var step: Step = .findingHomeAssistant
    @Published private(set) var address = ""
    @Published private(set) var haConnected = false
    @Published private(set) var deckPluggedIn = false
    @Published private(set) var deckAnswering = false
    @Published private(set) var startsWithMac = false
    @Published private(set) var lastError: String?
    /// True for this run only, when the app has just moved itself to Applications.
    @Published private(set) var justInstalled = false
    /// The version Home Assistant goes with, when it is not the one running.
    @Published private(set) var updateTo: String?
    @Published private(set) var updating: String?

    /// The one Service the app makes. Held here so the work that happens off the
    /// main thread can find its way back without passing the object around.
    static private(set) var current: Service?

    private var settings: Settings!
    private var link: Link!
    private let deck = Deck()
    private var finder: HomeAssistantFinder?

    private var haUp = false
    private var lastStatus = Date.distantPast
    private var statusBody = Data()
    private var announced = false
    private var deckSeenAt: Date?
    private var ticker: Timer?

    private let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    // ------------------------------------------------------------ starting up

    func start() {
        Service.current = self
        if UserDefaults.standard.bool(forKey: Installer.movedKey) {
            justInstalled = true
            UserDefaults.standard.removeObject(forKey: Installer.movedKey)
        }
        startsWithMac = (SMAppService.mainApp.status == .enabled)
        if let paired = Pairing.findBesideTheApp() {
            Pairing.write(paired)        // Home Assistant sent us its address and our key
        }
        settings = loadSettings(url: nil)
        address = settings.url

        deck.onAttach = { [weak self] in self?.deckArrived() }
        deck.onDetach = { [weak self] in self?.deckWentAway() }
        deck.onMessage = { [weak self] m in self?.fromDeck(m) }
        deck.start()

        if Pairing.haveSettingsFile() {
            connect()
        } else {
            findHomeAssistant()
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Look for Home Assistant on the network, so nobody has to type an address.
    func findHomeAssistant() {
        step = .findingHomeAssistant
        finder = HomeAssistantFinder { [weak self] found in
            Task { @MainActor in
                guard let self = self else { return }
                if let url = found {
                    self.setAddress(url)
                } else if !Pairing.haveSettingsFile() {
                    self.step = .noHomeAssistant
                }
            }
        }
        finder?.start()
    }

    /// The address typed into the window, when finding it did not work.
    func setAddress(_ url: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return }
        if !u.hasPrefix("http://") && !u.hasPrefix("https://") { u = "http://" + u }
        settings = loadSettings(url: u)
        address = settings.url
        connect()
    }

    private func connect() {
        link = Link(settings: settings)
        link.onReady = { [weak self] in Task { @MainActor in self?.linkReady() } }
        link.onVersion = { [weak self] want in
            Task { @MainActor in
                guard let self = self else { return }
                self.updateTo = Service.newer(want, than: bridgeVersion) ? want : nil
            }
        }
        link.onUpdateNow = { [weak self] in
            Task { @MainActor in self?.update() }
        }
        link.onSetUpDeck = { [weak self] in
            Task { @MainActor in self?.setUpDeck() }
        }
        link.onAppAt = { [weak self] token in
            Task { @MainActor in self?.fetchUpdate(token: token) }
        }
        link.onDown = { [weak self] in Task { @MainActor in self?.linkDown() } }
        link.onDeckMessage = { [weak self] m in
            Task { @MainActor in
                guard let self = self, self.deck.attached else { return }
                self.deck.send(m)
            }
        }
        link.connect()
        restate()
    }

    // ------------------------------------------------------------ the deck

    private func deckArrived() {
        deckPluggedIn = true
        deckSeenAt = Date()
        ping()
        restate()
    }

    private func deckWentAway() {
        deckPluggedIn = false
        deckAnswering = false
        lastStatus = .distantPast
        statusBody = Data()
        reconcile()
        restate()
    }

    private func fromDeck(_ m: Data) {
        switch m.first {
        case 0x81:
            lastStatus = Date()
            deckAnswering = true
            let body = m.dropFirst()
            if Data(body) != statusBody {
                statusBody = Data(body)
                if announced { link?.sendDeckMessage(m) }
            }
            reconcile()
            restate()
        case 0x82:
            if announced { link?.sendDeckMessage(m) }
        default:
            break
        }
    }

    private var deckAlive: Bool { deck.attached && Date().timeIntervalSince(lastStatus) < 6 }

    private func ping() {
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

    private func reconcile() {
        guard let link = link else { return }
        let should = link.ready && deckAlive
        if should && !announced {
            announced = true
            link.sendJSON(["type": "deck", "status": statusBody.base64EncodedString()])
        } else if !should && announced {
            announced = false
            if link.ready { link.sendJSON(["type": "deck_gone"]) }
        }
        if link.ready != haUp { haUp = link.ready; ping() }
    }

    private func linkReady() { haConnected = true; reconcile(); restate() }
    private func linkDown() { haConnected = false; reconcile(); restate() }

    private func tick() {
        ping()
        reconcile()
        deckAnswering = deckAlive
        restate()
    }

    /// Work out which of the steps the user is on. Nothing here changes anything.
    private func restate() {
        if case .settingUpDeck = step { return }     // leave it alone while it runs
        if !Pairing.haveSettingsFile() && link == nil {
            if step != .findingHomeAssistant { step = .noHomeAssistant }
            return
        }
        if !deck.attached {
            step = .noDeck
            return
        }
        // Plugged in but silent for long enough means it is still running the app it
        // came with: ours answers every ping. Six seconds is three pings.
        if !deckAlive {
            // Ours answers every ping; the software it came with never does. So a
            // few seconds of silence is the test — and it has to be said out loud,
            // because a window with two green lights and a dead button looks broken.
            if let seen = deckSeenAt, Date().timeIntervalSince(seen) > 6 {
                step = .deckNeedsSettingUp
            } else {
                step = .checkingDeck
            }
            return
        }
        step = haConnected ? .ready : .waitingToBeAllowed
    }

    // ------------------------------------------------------------ setting up the deck

    func setUpDeck() {
        step = .settingUpDeck("Looking for the deck…")
        // The deck restarts in the middle of this. Let go of the channel first,
        // or it comes back able to talk but not to listen.
        deck.letGo()
        let say: @Sendable (String) -> Void = { line in
            Task { @MainActor in Service.current?.step = .settingUpDeck(line) }
        }
        Task {
            let result = await Task.detached { DeckInstaller.run(say: say) }.value
            await MainActor.run { Service.current?.finishedSettingUp(result) }
        }
    }

    private func finishedSettingUp(_ result: DeckInstaller.Result) {
        switch result {
        case .success:
            lastError = nil
            deckSeenAt = Date()
            deck.lookAgain()             // fresh channel, both ways
            step = .noDeck               // it restarts its app; the next ping finds it
        case .failure(let why):
            lastError = why
            deck.lookAgain()             // whatever went wrong, take the deck back
            step = .deckNeedsSettingUp
        }
    }

    // ------------------------------------------------------------ keeping itself current

    /// Is `offered` a later version than `running`?
    ///
    /// Home Assistant counts in threes (3.2.0) and the app in twos (3.2), so
    /// they are compared a number at a time with the missing ones taken as
    /// nought. Anything unreadable counts as no update rather than a loop of
    /// offering one.
    static func newer(_ offered: String, than running: String) -> Bool {
        let a = offered.split(separator: ".").map { Int($0) ?? -1 }
        let b = running.split(separator: ".").map { Int($0) ?? -1 }
        if a.contains(-1) || b.contains(-1) { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Ask Home Assistant for somewhere to fetch the new app from.
    func update() {
        guard updating == nil else { return }
        updating = "Asking Home Assistant…"
        link?.sendJSON(["type": "want_app"])
    }

    private func fetchUpdate(token: String) {
        guard updating != nil, let base = URL(string: settings.url) else { return }
        let url = base.appendingPathComponent("api/ulanzi_deck/companion-app").appendingPathComponent(token)
        Updater.apply(from: url) { line in
            Task { @MainActor in Service.current?.updating = line }
        } done: { result in
            Task { @MainActor in
                guard let self = Service.current else { return }
                self.updating = nil
                if case .failure(let why) = result { self.lastError = why }
            }
        }
    }

    // ------------------------------------------------------------ starting with the Mac

    func setStartsWithMac(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            startsWithMac = (SMAppService.mainApp.status == .enabled)
        } catch {
            lastError = "Could not change whether it launches when the computer starts: \(error.localizedDescription)"
        }
    }
}
