import Foundation

/// Keeps the region values the device reported before GestaltEdit ever wrote
/// them, so "restore original region" has something exact to go back to.
enum RegionStore {
    private static let storageKey = "RegionSnapshot"

    static let regionCodeKey = "h63QSdBCiT/z0WU6rdQv6Q"
    static let salesSuffixKey = "yK+xavymRGZ3xWc1tb8XDg"

    struct Snapshot {
        let code: String?
        let suffix: String?
        let capturedAt: Date
    }

    static func snapshot() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let object = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let date = object["date"] as? Date else {
            return nil
        }
        let values = object["values"] as? [String: Any] ?? [:]
        return Snapshot(
            code: values[regionCodeKey] as? String,
            suffix: values[salesSuffixKey] as? String,
            capturedAt: date
        )
    }

    /// Stores the region once. Later calls are ignored so a changed region can
    /// never overwrite the original snapshot.
    static func captureIfNeeded(from cacheExtra: [String: Any]) {
        guard snapshot() == nil else { return }
        var values: [String: Any] = [:]
        if let code = cacheExtra[regionCodeKey] { values[regionCodeKey] = code }
        if let suffix = cacheExtra[salesSuffixKey] { values[salesSuffixKey] = suffix }
        guard !values.isEmpty else { return }
        let object: [String: Any] = ["values": values, "date": Date()]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: object,
            format: .binary,
            options: 0
        ) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
