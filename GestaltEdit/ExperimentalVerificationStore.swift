import Foundation

enum ExperimentalResult: String, Codable, CaseIterable, Identifiable {
    case unverified
    case works
    case noEffect
    case sideEffect

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unverified: String(localized: "Unverified")
        case .works: String(localized: "Works")
        case .noEffect: String(localized: "No effect")
        case .sideEffect: String(localized: "Has side effects")
        }
    }

    var symbol: String {
        switch self {
        case .unverified: "questionmark.circle"
        case .works: "checkmark.circle.fill"
        case .noEffect: "minus.circle"
        case .sideEffect: "exclamationmark.triangle.fill"
        }
    }

    /// Sort order for the exported report: verified results first.
    var rank: Int {
        switch self {
        case .works: 0
        case .sideEffect: 1
        case .noEffect: 2
        case .unverified: 3
        }
    }
}

struct ExperimentalVerification: Codable {
    var result: ExperimentalResult
    var updatedAt: Date
}

enum ExperimentalVerificationStore {
    private static let storageKey = "ExperimentalVerification"

    static func load() -> [String: ExperimentalVerification] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: ExperimentalVerification].self, from: data) else {
            return [:]
        }
        return map
    }

    static func save(_ map: [String: ExperimentalVerification]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
