import Foundation

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
