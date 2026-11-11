import Foundation

/// Remembers what this app wrote for the current iPadOS mode, so the mode can be
/// reverted later without re-parsing CacheData from scratch.
enum IPadModeStore {
    private static let defaultsKey = "IPadModeRecord"

    static func load() -> IPadModeRecord? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(IPadModeRecord.self, from: data)
    }

    static func save(_ record: IPadModeRecord?) {
        guard let record,
              let data = try? JSONEncoder().encode(record) else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
