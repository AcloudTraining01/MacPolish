import Foundation
import MPCore

final class HelperListener: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private let allowedPrefixes: Set<String> = [
        "/Library/Caches/",
        "/var/log/",
        "/private/var/log/",
    ]

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func deletePaths(_ paths: [String], moveToTrash: Bool, reply: @escaping (Bool, String?) -> Void) {
        let fm = FileManager.default
        for path in paths {
            guard isAllowed(path) else {
                reply(false, "Path not in allowlist: \(path)")
                return
            }
            let url = URL(fileURLWithPath: path)
            do {
                if moveToTrash {
                    var resultURL: NSURL?
                    try fm.trashItem(at: url, resultingItemURL: &resultURL)
                } else {
                    try fm.removeItem(at: url)
                }
            } catch {
                reply(false, "Failed to delete \(path): \(error.localizedDescription)")
                return
            }
        }
        reply(true, nil)
    }

    func runMaintenanceScript(_ script: String, reply: @escaping (Bool, String?) -> Void) {
        let allowed = ["periodic", "purge", "mdutil", "dscacheutil"]
        guard allowed.contains(where: { script.hasPrefix($0) }) else {
            reply(false, "Script not allowed: \(script)")
            return
        }
        reply(true, nil)
    }

    func flushDNSCache(reply: @escaping (Bool, String?) -> Void) {
        reply(true, nil)
    }

    func reindexSpotlight(volume: String, reply: @escaping (Bool, String?) -> Void) {
        reply(true, nil)
    }

    func deleteTimeMachineSnapshot(_ snapshot: String, reply: @escaping (Bool, String?) -> Void) {
        guard snapshot.hasPrefix("com.apple.TimeMachine.") else {
            reply(false, "Invalid snapshot name: \(snapshot)")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["deletelocalsnapshots", snapshot]
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                reply(true, nil)
            } else {
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                reply(false, message ?? "tmutil exited with status \(process.terminationStatus)")
            }
        } catch {
            reply(false, "Failed to launch tmutil: \(error.localizedDescription)")
        }
    }

    func getHelperVersion(reply: @escaping (String) -> Void) {
        reply("0.1.0")
    }

    private func isAllowed(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != URL(fileURLWithPath: path).standardizedFileURL.path {
            return false
        }
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let userAllowed = [
            "\(homeDir)/Library/Caches/",
            "\(homeDir)/Library/Logs/",
            "\(homeDir)/.Trash/",
        ]
        return allowedPrefixes.contains(where: { resolved.hasPrefix($0) })
            || userAllowed.contains(where: { resolved.hasPrefix($0) })
    }
}
