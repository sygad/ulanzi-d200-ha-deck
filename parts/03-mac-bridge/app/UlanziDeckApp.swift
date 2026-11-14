// UlanziDeckApp.swift — the window.
//
// It has one job: say what is happening in a sentence, and show at most one
// button, which is whatever the next thing to do happens to be. There are no
// settings, no tabs and nothing to configure. When everything is working it
// says so and the button goes away.

import SwiftUI
import ServiceManagement

@main
struct UlanziDeckApp: App {
    @StateObject private var service = Service()

    var body: some Scene {
        Window("Ulanzi Deck", id: "main") {
            MainView(service: service)
                .frame(width: 420)
                .fixedSize(horizontal: false, vertical: true)
                .onAppear { service.start() }
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra("Ulanzi Deck", systemImage: service.menuIcon) {
            Text(service.menuSummary)
            Divider()
            Button("Open Ulanzi Deck") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

struct MainView: View {
    @ObservedObject var service: Service
    @State private var typedAddress = ""

    var body: some View {
        if setupTime { setUp } else { everyday }
    }

    // ---------------------------------------------------------- the one decision
    //
    // This is the only moment the app asks for anything, and it is asked of
    // somebody who has just been told by macOS that we might be malware. So it
    // says what is true and nothing else: both ends are there, do you want to go
    // ahead. No explanation they did not ask for, no settings, no second colour.

    private var setupTime: Bool {
        if case .deckNeedsSettingUp = service.step { return service.haConnected && service.deckPluggedIn }
        if case .settingUpDeck = service.step { return true }
        return false
    }

    private var working: String? {
        if case .settingUpDeck(let line) = service.step { return line }
        return nil
    }

    private var setUp: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(working == nil ? "Ready to set up your deck" : "Setting up your deck")
                .font(.title3.weight(.medium))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                row("Home Assistant", colour: .green, text: "connected")
                row("Deck", colour: .green, text: "connected")
            }

            if let working = working {
                Text(working).font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { NSApplication.shared.keyWindow?.close() }
                    Button("Proceed") { service.setUpDeck() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(26)
    }

    // ---------------------------------------------------------- every other time

    private var everyday: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ulanzi Deck").font(.title2.weight(.medium))
                    Text(headline).font(.callout).foregroundStyle(.secondary)
                }
            }

            if let detail = detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .noHomeAssistant = service.step {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Home Assistant address").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("homeassistant.local:8123", text: $typedAddress)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { service.setAddress(typedAddress) }
                        Button("Connect") { service.setAddress(typedAddress) }
                            .disabled(typedAddress.isEmpty)
                    }
                }
            }

            if let error = service.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                row("Home Assistant",
                    colour: service.haConnected ? .green : .secondary.opacity(0.4),
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
                if let (title, action) = button {
                    Button(title, action: action)
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                }
            }
        }
        .padding(22)
    }

    private func row(_ name: String, colour: Color, text: String) -> some View {
        GridRow {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(name).foregroundStyle(.secondary)
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.callout)
    }

    /// A deck waiting to be set up is not a fault, so it is not drawn as one:
    /// amber and "ready to set up", beside the button that does it.
    private var deckColour: Color {
        if service.deckAnswering { return .green }
        if service.deckPluggedIn { return .orange }
        return .secondary.opacity(0.4)
    }

    private var deckText: String {
        if service.deckAnswering { return "connected" }
        guard service.deckPluggedIn else { return "not plugged in" }
        if case .deckNeedsSettingUp = service.step { return "ready to set up" }
        if case .settingUpDeck = service.step { return "setting up…" }
        return "starting up…"
    }

    private var busy: Bool {
        if case .settingUpDeck = service.step { return true }
        if case .findingHomeAssistant = service.step { return true }
        return false
    }

    private var headline: String {
        switch service.step {
        case .findingHomeAssistant: return "Looking for Home Assistant…"
        case .noHomeAssistant: return "Where is Home Assistant?"
        case .waitingToBeAllowed: return "Waiting for Home Assistant"
        case .noDeck: return "Plug in your deck"
        case .deckNeedsSettingUp: return "Your deck is ready to set up"
        case .settingUpDeck: return "Setting up your deck"
        case .ready: return "Everything is working"
        }
    }

    private var detail: String? {
        switch service.step {
        case .findingHomeAssistant:
            return nil
        case .noHomeAssistant:
            return "It was not found on this network, so it needs typing in once."
        case .waitingToBeAllowed:
            return "Open Ulanzi Deck in the Home Assistant sidebar and press Allow. "
                 + "This only happens the first time."
        case .noDeck:
            return "Plug the deck into this Mac with the cable it came with."
        case .deckNeedsSettingUp:
            return "Nothing is wrong: it is still running Ulanzi's own software. Press the "
                 + "button and it takes a few seconds. Ulanzi's copy is kept, so you can put "
                 + "it back whenever you like."
        case .settingUpDeck(let line):
            return line
        case .ready:
            return "Set up your keys in the Ulanzi Deck panel in Home Assistant."
        }
    }

    private var button: (String, () -> Void)? {
        switch service.step {
        case .deckNeedsSettingUp: return ("Set up my deck", { service.setUpDeck() })
        case .noHomeAssistant: return nil
        case .findingHomeAssistant: return ("Looking…", {})
        case .settingUpDeck: return ("Working…", {})
        default: return nil
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
