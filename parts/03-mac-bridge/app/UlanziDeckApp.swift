// UlanziDeckApp.swift — the window.
//
// It has one job: say what is happening in a sentence, and show at most one
// button, which is whatever the next thing to do happens to be. There are no
// settings, no tabs and nothing to configure. When everything is working it
// says so and the button goes away.

import SwiftUI
import ServiceManagement

/// Where the app lives.
///
/// The menu bar beside the clock, and nothing in the Dock. It is a thing that
/// carries USB traffic for as long as the Mac is on; it is not a document you
/// open, so it does not sit in the Dock all day pretending to be one.
///
/// Menu-bar-only was tried once before and taken out again, because marking the
/// app LSUIElement stopped SwiftUI opening its `Window` scene at all: 1.8
/// launched to an empty screen, "Open Ulanzi Deck" opened nothing, and closing
/// the last window of a menu bar app ended it. Three faults from one line of
/// plist, in the most anxious minute of the install.
///
/// The plist line is back, but the window is no longer a SwiftUI scene. It is an
/// NSWindow this delegate makes and keeps, which an accessory app is perfectly
/// able to show. That is the one thing that failed before, so it is the one
/// thing that changed. The Dock presence is never toggled at runtime either —
/// that was its own separate fault, windows vanishing as focus moved.
/// What this copy of the app is, for the window and the menu. Nobody should have
/// to look in Get Info to find out which one they are running.
let appVersion: String = {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    return v.map { "Version \($0)" } ?? ""
}()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let service = Service()

    func applicationDidFinishLaunching(_ note: Notification) {
        service.start()                       // reads the pairing file, while beside it
        if Installer.settleIn() { return }    // moving to Applications; this copy is going
        // macOS remembers how a window was left and restores it. A version of
        // this app closed its own window at startup, so every launch afterwards
        // restored a closed window and it looked dead. It does not get to
        // remember, and the window is shown on purpose at every launch.
        DispatchQueue.main.async { [weak self] in self?.comeBack() }
    }

    /// Closing the window puts it away; it does not stop the app carrying the
    /// deck's traffic. Quit is in the menu bar, where it belongs.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows visible: Bool) -> Bool {
        comeBack()
        return true
    }

    /// The menu bar glyph: a template image, so macOS tints it for light, dark
    /// and whatever the wallpaper is doing behind it. 16pt square with a 2x
    /// alongside; the bar allows 22pt and asks for no padding of our own.
    static let menuIcon: NSImage = {
        let img = Bundle.main.image(forResource: "menubar") ?? NSImage(size: NSSize(width: 16, height: 16))
        img.isTemplate = true
        img.size = NSSize(width: 16, height: 16)
        return img
    }()

    /// The one window, made once and kept.
    ///
    /// isReleasedWhenClosed is off because closing it only puts it away — the app
    /// carries on carrying the deck's traffic, and the next Open hands back the
    /// same window rather than a new one. macOS is not allowed to remember it
    /// being closed: a version of this app restored a closed window at every
    /// launch after the first and looked dead.
    private var window: NSWindow?

    func comeBack() {
        if window == nil {
            let w = NSWindow(contentViewController:
                NSHostingController(rootView: MainView(service: service)))
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.title = "Ulanzi Deck"
            w.isReleasedWhenClosed = false
            w.isRestorable = false
            w.center()
            window = w
        }
        // An accessory app has to say so to come forward; without this the
        // window opens behind whatever you were looking at.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@main
struct UlanziDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar item is the whole of the app's scenery. The window is not a
    // scene any more; see AppDelegate for why.
    var body: some Scene {
        MenuBarExtra {
            MenuContents(service: delegate.service) { delegate.comeBack() }
        } label: {
            MenuLabel(service: delegate.service)
        }
    }
}

/// The menu bar itself. A dot beside the keys when there is an update waiting,
/// drawn rather than baked into the icon so it stays sharp at any size.
struct MenuLabel: View {
    @ObservedObject var service: Service

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: AppDelegate.menuIcon)
            if service.updateTo != nil {
                Circle().frame(width: 5, height: 5)
            }
        }
    }
}

struct MenuContents: View {
    @ObservedObject var service: Service
    let open: () -> Void

    var body: some View {
        // "Ulanzi Deck" is the deck, the Home Assistant panel and this app all at
        // once, so a version beside it says nothing about which of the three it
        // belongs to. The panel calls this part the connector app; so does this.
        Text("Connector app — \(appVersion.replacingOccurrences(of: "Version ", with: ""))")
        Text(service.menuSummary)
        if let newer = service.updateTo {
            Divider()
            Button("Update to \(newer)…") {
                open()
                service.update()
            }
        }
        Divider()
        Button("Open connector app", action: open)
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}

/// One window, one shape, always the same.
///
/// Everything on it is on it all the time: the sentence saying what is
/// happening, both lights, the toggle, and the button. Nothing appears or
/// disappears as the state changes — only the words, the colours and whether
/// the button can be pressed. Controls that come and go make a working app
/// feel broken, which is exactly what happened to the versions before this.
struct MainView: View {
    @ObservedObject var service: Service
    @State private var typedAddress = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ulanzi Deck connector").font(.title2.weight(.medium))
                    Text(headline).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if case .noHomeAssistant = service.step {
                HStack {
                    TextField("homeassistant.local:8123", text: $typedAddress)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { service.setAddress(typedAddress) }
                    Button("Connect") { service.setAddress(typedAddress) }
                        .disabled(typedAddress.isEmpty)
                }
            }

            if service.justInstalled {
                Text("Moved to your Applications folder, so it is not in Downloads any more.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let updating = service.updating {
                Text(updating).font(.callout).foregroundStyle(.secondary)
            } else if let newer = service.updateTo {
                HStack(spacing: 10) {
                    Text("Version \(newer) is available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Update") { service.update() }
                        .controlSize(.small)
                }
            }

            if let error = service.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                row("Home Assistant", colour: service.haConnected ? .green : .secondary.opacity(0.35),
                    text: service.haConnected ? service.address : "not connected")
                row("Deck", colour: deckColour, text: deckText)
            }

            HStack {
                Toggle("Launch when computer starts", isOn: Binding(
                    get: { service.startsWithMac },
                    set: { service.setStartsWithMac($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button(buttonTitle) { service.setUpDeck() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
            }
        }
        .padding(22)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ name: String, colour: Color, text: String) -> some View {
        GridRow {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(name).foregroundStyle(.secondary)
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.callout)
    }

    /// Only ever pressable when there is something to press it for.
    private var canProceed: Bool {
        if case .deckNeedsSettingUp = service.step { return service.haConnected && service.deckPluggedIn }
        return false
    }

    private var buttonTitle: String {
        if case .settingUpDeck = service.step { return "Working…" }
        return "Proceed"
    }

    private var deckColour: Color {
        if service.deckAnswering { return .green }
        if case .checkingDeck = service.step { return .orange }
        if service.deckPluggedIn { return .green }
        return .secondary.opacity(0.35)
    }

    private var deckText: String {
        if service.deckAnswering { return "connected" }
        guard service.deckPluggedIn else { return "not plugged in" }
        if case .settingUpDeck = service.step { return "setting up…" }
        if case .checkingDeck = service.step { return "checking…" }
        return "connected"
    }

    private var headline: String {
        switch service.step {
        case .findingHomeAssistant: return "Looking for Home Assistant…"
        case .noHomeAssistant: return "Where is Home Assistant?"
        case .waitingToBeAllowed: return "Waiting for Home Assistant"
        case .noDeck: return "Plug in your deck"
        case .checkingDeck: return "Checking your deck"
        case .deckNeedsSettingUp: return "Ready to set up your deck"
        case .settingUpDeck: return "Setting up your deck"
        case .ready: return "Everything is working"
        }
    }

    private var detail: String {
        switch service.step {
        case .findingHomeAssistant:
            return "Looking on this network."
        case .noHomeAssistant:
            return "It was not found on this network, so it needs typing in once."
        case .waitingToBeAllowed:
            return "Open the Ulanzi Deck panel in Home Assistant and press Allow. "
                 + "This only happens the first time."
        case .noDeck:
            return "Plug the deck into this Mac with the cable it came with."
        case .checkingDeck:
            return "Seeing what it is running. A few seconds."
        case .deckNeedsSettingUp:
            return "Press Proceed and it takes a few seconds. Ulanzi's own software is "
                 + "kept on the deck, so it can be put back."
        case .settingUpDeck(let line):
            return line
        case .ready:
            return "Set up your keys in the Ulanzi Deck panel in Home Assistant."
        }
    }
}

extension Service {
    var menuIcon: String {
        if case .ready = step { return "square.grid.3x3.fill" }
        return "square.grid.3x3"
    }
    var menuSummary: String {
        if case .ready = step { return "Deck connected" }
        if !deckPluggedIn { return "No deck plugged in" }
        if !haConnected { return "Home Assistant not connected" }
        return "Setting up"
    }
}
