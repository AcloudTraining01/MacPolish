import Foundation

public struct AppEnvironment: Sendable {
    public let quarantine: Quarantine
    public let pathClassifier: PathClassifier

    public init(
        quarantine: Quarantine = Quarantine(),
        pathClassifier: PathClassifier = PathClassifier()
    ) {
        self.quarantine = quarantine
        self.pathClassifier = pathClassifier
    }
}
