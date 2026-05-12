import Foundation
import MPCore
import Security

final class HelperListener: NSObject, NSXPCListenerDelegate, HelperProtocol {

    private static let clientIdentifier = "com.macpolish.app"

    private static let clientRequirement: SecRequirement? = {
        var requirement: SecRequirement?
        let reqString = "identifier \"\(clientIdentifier)\"" as CFString
        SecRequirementCreateWithString(reqString, [], &requirement)
        return requirement
    }()

    private static let maintenanceScripts: [String: (executable: String, arguments: [String])] = [
        "periodic_daily":    ("/usr/sbin/periodic",   ["daily"]),
        "periodic_weekly":   ("/usr/sbin/periodic",   ["weekly"]),
        "periodic_monthly":  ("/usr/sbin/periodic",   ["monthly"]),
        "purge":             ("/usr/sbin/purge",      []),
        "mdutil_erase":      ("/usr/bin/mdutil",      ["-Ea"]),
        "dscacheutil_flush": ("/usr/bin/dscacheutil", ["-flushcache"]),
    ]

    private let allowedPrefixes: Set<String> = [
        "/Library/Caches/",
        "/var/log/",
        "/private/var/log/",
    ]

    // MARK: - NSXPCListenerDelegate

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard verifyClient(newConnection) else {
            AuditLog.record(
                action: "connectionRejected",
                success: false,
                error: "Caller failed code signature requirement"
            )
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func deletePaths(_ paths: [String], moveToTrash: Bool, reply: @escaping (Bool, String?) -> Void) {
        let fm = FileManager.default
        for path in paths {
            guard isAllowed(path) else {
                let err = "Path not in allowlist: \(path)"
                AuditLog.record(action: "deletePaths", success: false, paths: paths, error: err)
                reply(false, err)
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
                let err = "Failed to delete \(path): \(error.localizedDescription)"
                AuditLog.record(action: "deletePaths", success: false, paths: paths, error: err)
                reply(false, err)
                return
            }
        }
        AuditLog.record(action: "deletePaths", success: true, paths: paths)
        reply(true, nil)
    }

    func runMaintenanceScript(_ script: String, reply: @escaping (Bool, String?) -> Void) {
        guard let entry = Self.maintenanceScripts[script] else {
            let err = "Unknown maintenance script: \(script)"
            AuditLog.record(action: "runMaintenanceScript:\(script)", success: false, error: err)
            reply(false, err)
            return
        }
        runProcess(
            executable: entry.executable,
            arguments: entry.arguments,
            action: "runMaintenanceScript:\(script)",
            reply: reply
        )
    }

    func flushDNSCache(reply: @escaping (Bool, String?) -> Void) {
        let (status1, stderr1) = runProcessSync(
            executable: "/usr/bin/dscacheutil",
            arguments: ["-flushcache"]
        )
        guard status1 == 0 else {
            let err = stderr1.isEmpty ? "dscacheutil exited with status \(status1)" : stderr1
            AuditLog.record(action: "flushDNSCache", success: false, error: err)
            reply(false, err)
            return
        }
        let (status2, stderr2) = runProcessSync(
            executable: "/usr/bin/killall",
            arguments: ["-HUP", "mDNSResponder"]
        )
        guard status2 == 0 else {
            let err = stderr2.isEmpty ? "killall -HUP mDNSResponder exited with status \(status2)" : stderr2
            AuditLog.record(action: "flushDNSCache", success: false, error: err)
            reply(false, err)
            return
        }
        AuditLog.record(action: "flushDNSCache", success: true)
        reply(true, nil)
    }

    func reindexSpotlight(volume: String, reply: @escaping (Bool, String?) -> Void) {
        guard isValidVolumePath(volume) else {
            let err = "Invalid volume path: \(volume)"
            AuditLog.record(action: "reindexSpotlight", success: false, paths: [volume], error: err)
            reply(false, err)
            return
        }
        let (status, stderr) = runProcessSync(
            executable: "/usr/bin/mdutil",
            arguments: ["-E", volume]
        )
        if status == 0 {
            AuditLog.record(action: "reindexSpotlight", success: true, paths: [volume])
            reply(true, nil)
        } else {
            let err = stderr.isEmpty ? "mdutil exited with status \(status)" : stderr
            AuditLog.record(action: "reindexSpotlight", success: false, paths: [volume], error: err)
            reply(false, err)
        }
    }

    func deleteTimeMachineSnapshot(_ snapshot: String, reply: @escaping (Bool, String?) -> Void) {
        guard snapshot.hasPrefix("com.apple.TimeMachine.") else {
            let err = "Invalid snapshot name: \(snapshot)"
            AuditLog.record(
                action: "deleteTimeMachineSnapshot",
                success: false,
                paths: [snapshot],
                error: err
            )
            reply(false, err)
            return
        }
        let (status, stderr) = runProcessSync(
            executable: "/usr/bin/tmutil",
            arguments: ["deletelocalsnapshots", snapshot]
        )
        if status == 0 {
            AuditLog.record(
                action: "deleteTimeMachineSnapshot",
                success: true,
                paths: [snapshot]
            )
            reply(true, nil)
        } else {
            let err = stderr.isEmpty ? "tmutil exited with status \(status)" : stderr
            AuditLog.record(
                action: "deleteTimeMachineSnapshot",
                success: false,
                paths: [snapshot],
                error: err
            )
            reply(false, err)
        }
    }

    func getHelperVersion(reply: @escaping (String) -> Void) {
        reply("0.1.0")
    }

    // MARK: - Validation

    // NSXPCConnection.auditToken is not part of the public API; KVC is the de-facto
    // standard accessor for it and has remained stable across macOS releases.
    private func verifyClient(_ connection: NSXPCConnection) -> Bool {
        guard let nsValue = connection.value(forKey: "auditToken") as? NSValue else {
            return false
        }
        let tokenSize = MemoryLayout<audit_token_t>.size
        var tokenData = Data(count: tokenSize)
        tokenData.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                nsValue.getValue(base, size: tokenSize)
            }
        }

        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let secCode = code else {
            return false
        }

        guard let requirement = Self.clientRequirement else { return false }
        return SecCodeCheckValidity(secCode, [], requirement) == errSecSuccess
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

    private func isValidVolumePath(_ volume: String) -> Bool {
        if volume == "/" { return true }
        guard volume.hasPrefix("/Volumes/") else { return false }
        let name = String(volume.dropFirst("/Volumes/".count))
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return false }
        return name.allSatisfy { c in
            c.isLetter || c.isNumber || c == "-" || c == "_" || c == " " || c == "."
        }
    }

    // MARK: - Process execution

    private func runProcess(
        executable: String,
        arguments: [String],
        action: String,
        reply: @escaping (Bool, String?) -> Void
    ) {
        let (status, stderr) = runProcessSync(executable: executable, arguments: arguments)
        if status == 0 {
            AuditLog.record(action: action, success: true)
            reply(true, nil)
        } else {
            let err = stderr.isEmpty ? "\(executable) exited with status \(status)" : stderr
            AuditLog.record(action: action, success: false, error: err)
            reply(false, err)
        }
    }

    private func runProcessSync(executable: String, arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, stderr)
        } catch {
            return (-1, "Failed to launch \(executable): \(error.localizedDescription)")
        }
    }
}
