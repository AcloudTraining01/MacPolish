import Foundation
import Photos
import MPCore

public actor PhotoLibraryScanner: MPCore.Scanner {
    public let category: ScanCategory = .photoLibrary
    private var currentResult: ScanResult?
    private var capturedAssetIDs: [String] = []
    private var isCancelled = false

    public static let screenshotAgeSeconds: TimeInterval = 180 * 24 * 3600

    public init() {}

    public enum AccessState: Sendable {
        case unknown
        case granted
        case limited
        case denied
        case restricted
    }

    public static func authorizationStatus() -> AccessState {
        let raw = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch raw {
        case .notDetermined: return .unknown
        case .authorized: return .granted
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unknown
        }
    }

    public static func requestAuthorization() async -> AccessState {
        await withCheckedContinuation { (continuation: CheckedContinuation<AccessState, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                continuation.resume(returning: authorizationStatus())
            }
        }
    }

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil
        capturedAssetIDs = []

        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                continuation.yield(ScanProgress(category: category, phase: .preparing))

                let access = Self.authorizationStatus()
                guard access == .granted || access == .limited else {
                    continuation.yield(ScanProgress(
                        category: category,
                        phase: .failed("Photos access not granted")
                    ))
                    continuation.finish()
                    return
                }

                let cutoff = Date(timeIntervalSinceNow: -Self.screenshotAgeSeconds) as NSDate
                let options = PHFetchOptions()
                options.predicate = NSPredicate(
                    format: "creationDate < %@ AND (mediaSubtypes & %d) != 0",
                    cutoff,
                    PHAssetMediaSubtype.photoScreenshot.rawValue
                )
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

                let assets = PHAsset.fetchAssets(with: .image, options: options)
                if isCancelled {
                    continuation.finish()
                    return
                }

                var items: [ScanItem] = []
                var ids: [String] = []
                var total: Int64 = 0
                let cancellation = Cancellation()
                assets.enumerateObjects { asset, _, stop in
                    if cancellation.isCancelled {
                        stop.pointee = true
                        return
                    }
                    let resources = PHAssetResource.assetResources(for: asset)
                    let size = (resources.first?.value(forKey: "fileSize") as? Int64) ?? 0
                    guard let url = URL(string: "photos://\(asset.localIdentifier)") else { return }
                    let label = Self.dateFormatter.string(from: asset.creationDate ?? .now)
                    items.append(ScanItem(
                        path: url,
                        name: "Screenshot — \(label)",
                        size: size,
                        category: .photoLibrary,
                        riskLevel: .safe,
                        lastModified: asset.creationDate
                    ))
                    ids.append(asset.localIdentifier)
                    total += size
                }

                if !isCancelled {
                    capturedAssetIDs = ids
                    currentResult = ScanResult(
                        category: category,
                        items: items,
                        totalSize: total,
                        scanDuration: Date().timeIntervalSince(startTime)
                    )
                    continuation.yield(ScanProgress(
                        category: category,
                        phase: .complete,
                        itemsFound: items.count,
                        bytesFound: total
                    ))
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func capturedAssetLocalIdentifiers() -> [String] { capturedAssetIDs }
    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() {
        currentResult = nil
        capturedAssetIDs = []
        isCancelled = false
    }

    public func deleteAssets(localIdentifiers: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assetList: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in assetList.append(asset) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetList as NSFastEnumeration)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: NSError(
                        domain: "MacPolish.Photos",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Delete was cancelled or refused"]
                    ))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private final class Cancellation: @unchecked Sendable {
        var isCancelled = false
    }
}
