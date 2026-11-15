// Updater.swift — replacing this app with a newer one.
//
// The new copy comes from Home Assistant, not from the internet: the same one
// address this app was told to trust, over the connection it is already on.
// Because this app does the downloading rather than a browser, the copy carries
// no quarantine, so macOS does not ask about it again — the warning, the
// settings and the two Open Anyways happen once in the life of the app.

import AppKit
import Foundation

enum Updater {

    enum Result {
        case success
        case failure(String)
    }

    /// Fetch the zip at `url`, put what is inside where this app is, and restart.
    static func apply(from url: URL, say: @escaping (String) -> Void,
                      done: @escaping (Result) -> Void) {
        say("Downloading…")
        URLSession.shared.downloadTask(with: url) { file, response, error in
            guard let file = file,
                  (response as? HTTPURLResponse)?.statusCode == 200, error == nil else {
                done(.failure("The update could not be downloaded. Try again in a moment."))
                return
            }
            say("Installing…")
            switch swapIn(zip: file) {
            case .failure(let why): done(.failure(why))
            case .success: done(.success)
            }
        }.resume()
    }

    private static func swapIn(zip: URL) -> Result {
        let fm = FileManager.default
        let here = Pairing.realHome
        let work = fm.temporaryDirectory.appendingPathComponent("ulanzi-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }

        do { try fm.createDirectory(at: work, withIntermediateDirectories: true) }
        catch { return .failure("There is nowhere to unpack the update.") }

        // ditto rather than unzip: it is what macOS uses, and it keeps the
        // permissions and the signature intact.
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        do { try ditto.run() } catch { return .failure("The update could not be unpacked.") }
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { return .failure("The update could not be unpacked.") }

        let fresh = work.appendingPathComponent(here.lastPathComponent)
        guard fm.fileExists(atPath: fresh.path) else {
            return .failure("The update did not contain the app.")
        }

        // Swap, keeping the old one until the new one is in place.
        let old = work.appendingPathComponent("previous.app")
        do {
            try fm.moveItem(at: here, to: old)
            do { try fm.moveItem(at: fresh, to: here) }
            catch {
                try? fm.moveItem(at: old, to: here)      // put it back
                return .failure("The update could not be put in place.")
            }
        } catch {
            return .failure("This copy of the app cannot be replaced from here.")
        }

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: here, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return .success
    }
}
