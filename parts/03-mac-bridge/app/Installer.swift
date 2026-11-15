// Installer.swift — putting itself where applications live.
//
// Downloading an app and then running it out of Downloads for ever is how
// something looks temporary. On its first run it moves itself to Applications
// and starts again from there, so after the one download there is an app on the
// Mac like any other.
//
// It happens after the pairing file has been read, because that file sits beside
// the download and is no use once we have moved away from it.

import AppKit
import Foundation

enum Installer {

    /// Move to Applications and relaunch. True means we are on our way out.
    static func settleIn() -> Bool {
        let here = Pairing.realHome
        let fm = FileManager.default

        // Already somewhere an application belongs.
        for home in applicationFolders where here.path.hasPrefix(home.path + "/") { return false }

        guard let folder = applicationFolders.first(where: { fm.isWritableFile(atPath: $0.path) })
        else { return false }

        let destination = folder.appendingPathComponent(here.lastPathComponent)
        do {
            if fm.fileExists(atPath: destination.path) {
                // Something of ours is already there. Prefer it to this copy.
                if destination.path != here.path { try? fm.removeItem(at: destination) }
                if fm.fileExists(atPath: destination.path) { return relaunch(at: destination) }
            }
            try fm.moveItem(at: here, to: destination)
        } catch {
            return false        // not worth bothering anybody about; carry on as we are
        }
        return relaunch(at: destination)
    }

    private static var applicationFolders: [URL] {
        var folders = [URL(fileURLWithPath: "/Applications")]
        if let mine = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            folders.append(mine)
        }
        return folders
    }

    /// Remembered across the relaunch, so the window can mention it once.
    static let movedKey = "movedToApplications"

    private static func relaunch(at app: URL) -> Bool {
        UserDefaults.standard.set(true, forKey: movedKey)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }
}
