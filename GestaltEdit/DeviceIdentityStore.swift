import Foundation

/// Keeps the identity values the device reported before GestaltEdit ever wrote
/// them, so "restore official identity" has something exact to go back to.
enum DeviceIdentityStore {
    private static let storageKey = "DeviceIdentitySnapshot"

    /// Keys that make up the device identity and the AI-spoofing extra flags.
    static let keys = [
        "0+nc/Udy4WNG8S+Q7a/s1A",
        "h9jDsbgj7xIVeIQ8S3/X3Q",
        "oYicEKzVTz4/CxxE05pEgQ",
        "5pYKlGnYYBzGvAlIU8RjEQ",
        "97JDvERpVwO+GHtthIh7hA",
        "A62OafQ85EJAiiqKn4agtg",
        "a3n5T9sFtlyQ74NEp9ESxg"
    ]

    struct Snapshot {
        let values: [String: Any]
        let capturedAt: Date
    }

    static func snapshot() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let object = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let values = object["values"] as? [String: Any],
              let date = object["date"] as? Date else {
            return nil
        }
        return Snapshot(values: values, capturedAt: date)
    }

    /// Stores the identity once. Later calls are ignored so a spoofed state can
    /// never overwrite the real device identity.
    static func captureIfNeeded(from cacheExtra: [String: Any]) {
        guard snapshot() == nil else { return }
        var values: [String: Any] = [:]
        for key in keys {
            if let value = cacheExtra[key] {
                values[key] = value
            }
        }
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
