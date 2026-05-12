import Foundation
import MPCore

public final class HelperClient: @unchecked Sendable {
    private var connection: NSXPCConnection?

    public init() {}

    public func connect() {
        let conn = NSXPCConnection(machServiceName: helperMachServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.resume()
        self.connection = conn
    }

    public func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    public var isConnected: Bool {
        connection != nil
    }

    public func deletePaths(_ paths: [String], moveToTrash: Bool) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperProtocol else {
                continuation.resume(throwing: HelperClientError.notConnected)
                return
            }

            proxy.deletePaths(paths, moveToTrash: moveToTrash) { success, errorMessage in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: HelperClientError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    public func runMaintenanceScript(_ script: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperProtocol else {
                continuation.resume(throwing: HelperClientError.notConnected)
                return
            }

            proxy.runMaintenanceScript(script) { success, errorMessage in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: HelperClientError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    public func flushDNSCache() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperProtocol else {
                continuation.resume(throwing: HelperClientError.notConnected)
                return
            }

            proxy.flushDNSCache { success, errorMessage in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: HelperClientError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    public func reindexSpotlight(volume: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperProtocol else {
                continuation.resume(throwing: HelperClientError.notConnected)
                return
            }

            proxy.reindexSpotlight(volume: volume) { success, errorMessage in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: HelperClientError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    public func getHelperVersion() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperProtocol else {
                continuation.resume(throwing: HelperClientError.notConnected)
                return
            }

            proxy.getHelperVersion { version in
                continuation.resume(returning: version)
            }
        }
    }
    public func deleteTimeMachineSnapshot(_ snapshot: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperProtocol else {
                continuation.resume(throwing: HelperClientError.notConnected)
                return
            }

            proxy.deleteTimeMachineSnapshot(snapshot) { success, errorMessage in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: HelperClientError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }
}

public enum HelperClientError: LocalizedError {
    case notConnected
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Helper tool is not connected."
        case .operationFailed(let msg): return "Helper operation failed: \(msg)"
        }
    }
}
