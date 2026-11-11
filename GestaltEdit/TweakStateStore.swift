import Foundation

/// Remembers what a tweak's keys held before GestaltEdit first wrote them, so
/// turning the tweak off can put the exact original values back instead of
/// guessing a global default.
enum TweakStateStore {
    private static let storageKey = "TweakOriginalValues"

    static func rememberedValues(for id: GestaltTweakID) -> [String: Any]? {
        load()[id.rawValue]
    }

    static func remember(_ values: [String: Any], for id: GestaltTweakID) {
        var map = load()
        map[id.rawValue] = values
        save(map)
    }

    static func forget(_ id: GestaltTweakID) {
        var map = load()
        guard map.removeValue(forKey: id.rawValue) != nil else { return }
        save(map)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func load() -> [String: [String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let object = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: [String: Any]] else {
            return [:]
        }
        return object
    }

    private static func save(_ map: [String: [String: Any]]) {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: map,
            format: .binary,
            options: 0
        ) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
