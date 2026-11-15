// DeckInstaller.swift — putting the deck app on the deck, from inside the Mac app.
//
// This is the one job that needs more than the USB data channel: a deck still
// running the software it came with is not listening on that channel, so the app
// has to be copied over the deck's debug port instead. That is plain adb, and a
// copy of it is carried inside this app (Apache 2.0, see NOTICE-adb.txt beside
// it), so nobody has to install anything.
//
// It does exactly what the old install.sh did, in the same order:
//   keep the deck's own app the first time, copy ours in, start it.
// Nothing outside /userdata on the deck is touched, and the deck's own app is
// kept at /userdata/vendor so it can be put back.

import Foundation

enum DeckInstaller {

    enum Result {
        case success
        case failure(String)
    }

    private static var adb: URL? { Bundle.main.url(forResource: "adb", withExtension: nil) }
    private static var deckApp: URL? { Bundle.main.url(forResource: "deckd", withExtension: nil) }
    private static var starterLayout: URL? { Bundle.main.url(forResource: "default-layout", withExtension: "bin") }

    /// Runs the whole thing on a background thread. `say` is called with a line to show.
    static func run(say: @escaping (String) -> Void) -> Result {
        guard let adb = adb, let deckApp = deckApp else {
            return .failure("This copy of the app is missing the files it needs to set up a deck.")
        }

        say("Looking for the deck…")
        // Versions up to 2.8 ran an adb server of their own on port 5137. One of
        // those left running still holds the deck, and nothing else can open it
        // while it does. That port was only ever ours, so it is safe to end it.
        _ = shell(adb, ["-P", "5137", "kill-server"])
        // adb keeps a server process of its own; start it where it cannot clash with
        // a copy the user may have installed themselves
        _ = shell(adb, ["start-server"])
        let devices = shell(adb, ["devices"])
        guard devices.out.split(separator: "\n").dropFirst().contains(where: { $0.contains("device") }) else {
            return .failure("The deck did not answer. Check it is plugged in with the cable it came "
                            + "with — some cables carry power only. If another program is using the "
                            + "deck, close it and try again.")
        }

        say("Keeping the deck's own software safe…")
        let keep = shell(adb, ["shell", """
            mkdir -p /userdata/deck /userdata/vendor
            if [ ! -f /userdata/vendor/UlanziDeckKey ]; then
              cp -p /userdata/UlanziDeckKey /userdata/vendor/UlanziDeckKey
            fi
            echo kept
            """])
        guard keep.out.contains("kept") else {
            return .failure("Could not write to the deck. Unplug it, plug it back in, and try again.")
        }

        say("Copying the app across…")
        let push = shell(adb, ["push", deckApp.path, "/userdata/UlanziDeckKey.new"])
        guard push.status == 0 else {
            return .failure("The copy to the deck did not finish. Unplug it, plug it back in, and try again.")
        }

        if let layout = starterLayout {
            let has = shell(adb, ["shell", "ls /userdata/deck/layout.bin 2>/dev/null"])
            if has.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                say("Giving it something to show…")
                // Not fatal: the deck works, it just has nothing on screen until
                // Home Assistant sends a layout. But it was being thrown away
                // entirely, so a deck that came up blank looked like a success.
                let pushed = shell(adb, ["push", layout.path, "/userdata/deck/layout.bin"])
                if pushed.status != 0 {
                    say("The starter screen did not copy across — the deck will be blank "
                        + "until Home Assistant sends your keys.")
                }
            }
        }

        say("Starting it…")
        let start = shell(adb, ["shell", """
            killall UlanziDeckKey 2>/dev/null
            chmod 755 /userdata/UlanziDeckKey.new
            mv /userdata/UlanziDeckKey.new /userdata/UlanziDeckKey || echo MOVEFAILED
            sync
            (setsid /userdata/UlanziDeckKey -platform linuxfb >/dev/null 2>&1 &)
            sleep 1
            ps | grep "[U]lanziDeckKey" >/dev/null && echo running || echo stopped
            """])
        // "running" on its own is not enough: if the move failed, the OLD app is
        // what started, and it would report success while changing nothing.
        if start.out.contains("MOVEFAILED") {
            return .failure("The new deck software could not be put in place, so the deck is "
                            + "still running the old one. Unplug it, plug it back in, and try again.")
        }
        guard start.out.contains("running") else {
            return .failure("The deck took the app but would not start it. Unplug it, plug it back in, and try again.")
        }

        say("Done.")
        return .success
    }

    /// Puts back the software the deck came with.
    static func putBackTheOriginal() -> Result {
        guard let adb = adb else { return .failure("This copy of the app cannot talk to a deck.") }
        let r = shell(adb, ["shell", """
            if [ -f /userdata/vendor/UlanziDeckKey ]; then
              killall UlanziDeckKey 2>/dev/null
              cp /userdata/vendor/UlanziDeckKey /userdata/UlanziDeckKey
              sync
              (setsid /userdata/UlanziDeckKey -platform linuxfb >/dev/null 2>&1 &)
              echo put-back
            else
              echo missing
            fi
            """])
        if r.out.contains("put-back") { return .success }
        if r.out.contains("missing") {
            return .failure("The deck's own software is not on it any more, so there is nothing to put back.")
        }
        return .failure("The deck did not answer.")
    }

    private static func shell(_ tool: URL, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = tool
        p.arguments = args
        // Use the ordinary adb port. A second server on a port of our own cannot
        // open a deck the user's own adb already has hold of, which shows up as
        // the deck not answering at all. Sharing one server avoids the fight.
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        env.removeValue(forKey: "ANDROID_ADB_SERVER_PORT")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
