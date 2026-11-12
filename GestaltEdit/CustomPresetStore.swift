import Foundation

/// A named set of tweaks the user saved from the currently applied state.
struct CustomPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Raw values of `GestaltTweakID`, kept as strings so an unknown preset from
    /// an older build can be skipped instead of breaking decoding.
    var tweakIDs: [String]
    var createdAt: Date
}

enum CustomPresetStore {
    private static let storageKey = "CustomPresets"

    static func list() -> [CustomPreset] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let presets = try? JSONDecoder().decode([CustomPreset].self, from: data) else {
            return []
        }
        return presets
    }

    static func save(_ presets: [CustomPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
