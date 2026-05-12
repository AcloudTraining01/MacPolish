import Foundation

@objc public protocol HelperProtocol {
    func deletePaths(
        _ paths: [String],
        moveToTrash: Bool,
        reply: @escaping (Bool, String?) -> Void
    )

    func runMaintenanceScript(
        _ script: String,
        reply: @escaping (Bool, String?) -> Void
    )

    func flushDNSCache(
        reply: @escaping (Bool, String?) -> Void
    )

    func reindexSpotlight(
        volume: String,
        reply: @escaping (Bool, String?) -> Void
    )

    func deleteTimeMachineSnapshot(
        _ snapshot: String,
        reply: @escaping (Bool, String?) -> Void
    )

    func getHelperVersion(
        reply: @escaping (String) -> Void
    )
}

public let helperMachServiceName = "com.macpolish.helper"
