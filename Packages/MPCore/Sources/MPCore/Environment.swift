import SwiftUI

private struct QuarantineKey: EnvironmentKey {
    static let defaultValue = Quarantine()
}

public extension EnvironmentValues {
    var quarantine: Quarantine {
        get { self[QuarantineKey.self] }
        set { self[QuarantineKey.self] = newValue }
    }
}
