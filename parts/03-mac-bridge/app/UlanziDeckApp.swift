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
                row("Home Assistant", ok: service.haConnected,
                    yes: service.address, no: "not connected")
                row("Deck", ok: service.deckAnswering,
                    yes: "connected", no: service.deckPluggedIn ? "plugged in, not answering" : "not plugged in")
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

    private func row(_ name: String, ok: Bool, yes: String, no: String) -> some View {
        GridRow {
            Circle()
                .fill(ok ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(name).foregroundStyle(.secondary)
            Text(ok ? yes : no).lineLimit(1).truncationMode(.middle)
        }
        .font(.callout)
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
        case .deckNeedsSettingUp: return "Your deck needs setting up"
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
            return "It is still running the software it came with. Setting it up takes a few "
                 + "seconds and keeps a copy of that software, so it can be put back."
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
