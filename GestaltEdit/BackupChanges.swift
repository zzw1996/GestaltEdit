import Foundation

/// What triggered a write, so a backup can say what it preceded.
enum BackupChangeSource: String, Codable, Hashable {
    case tweaks
    case fieldEditor
    case restore
    case automation

    var label: String {
        switch self {
        case .tweaks: String(localized: "Tweaks Applied")
        case .fieldEditor: String(localized: "Field Editor")
        case .restore: String(localized: "Backup Restored")
        case .automation: String(localized: "Automation")
        }
    }
}

struct BackupChange: Codable, Hashable, Identifiable {
    let key: String
    let oldValue: String?
    let newValue: String?

    var id: String { key }

    var detail: String {
        switch (oldValue, newValue) {
        case (nil, let newValue?):
            String(format: String(localized: "added → %@"), newValue)
        case (let oldValue?, nil):
            String(format: String(localized: "removed (was %@)"), oldValue)
        case (let oldValue?, let newValue?):
            "\(oldValue) → \(newValue)"
        default:
            ""
        }
    }
}

/// The change set that followed a given backup snapshot.
struct BackupChangeSet: Codable, Hashable {
    let source: BackupChangeSource
    let added: Int
    let modified: Int
    let removed: Int
    let changes: [BackupChange]
    let truncated: Bool

    var total: Int { added + modified + removed }

    var summary: String {
        String(
            format: String(localized: "%@ · +%lld ~%lld -%lld"),
            source.label,
            added,
            modified,
            removed
        )
    }
}

enum GestaltChangeDiff {
    /// Keep the sidecar small enough to stay readable on screen.
    static let limit = 40

    static func changes(
        old: [String: Any],
        new: [String: Any],
        source: BackupChangeSource
    ) -> BackupChangeSet {
        let oldValues = flatten(old)
        let newValues = flatten(new)
        var changes: [BackupChange] = []
        var added = 0
        var modified = 0
        var removed = 0

        for key in Set(oldValues.keys).union(newValues.keys).sorted() {
            let oldValue = oldValues[key]
            let newValue = newValues[key]
            switch (oldValue, newValue) {
            case (nil, let newValue?):
                added += 1
                changes.append(.init(key: key, oldValue: nil, newValue: describe(newValue)))
            case (let oldValue?, nil):
                removed += 1
                changes.append(.init(key: key, oldValue: describe(oldValue), newValue: nil))
            case (let oldValue?, let newValue?) where !valuesEqual(oldValue, newValue):
                modified += 1
                changes.append(
                    .init(key: key, oldValue: describe(oldValue), newValue: describe(newValue))
                )
            default:
                continue
            }
        }

        return BackupChangeSet(
            source: source,
            added: added,
            modified: modified,
            removed: removed,
            changes: Array(changes.prefix(limit)),
            truncated: changes.count > limit
        )
    }

    /// CacheExtra is a dictionary of hash-like keys; flattening it makes each
    /// individual field visible in the log instead of one opaque blob.
    private static func flatten(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            if key == "CacheExtra", let cacheExtra = value as? [String: Any] {
                for (innerKey, innerValue) in cacheExtra {
                    result["CacheExtra/\(innerKey)"] = innerValue
                }
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func valuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let lhs = lhs as? Data, let rhs = rhs as? Data {
            return lhs == rhs
        }
        if let lhs = lhs as? [String: Any], let rhs = rhs as? [String: Any] {
            return NSDictionary(dictionary: lhs).isEqual(to: rhs)
        }
        if let lhs = lhs as? [Any], let rhs = rhs as? [Any] {
            return NSArray(array: lhs).isEqual(to: rhs)
        }
        if let lhs = lhs as? NSObject, let rhs = rhs as? NSObject {
            return lhs.isEqual(rhs)
        }
        return describe(lhs) == describe(rhs)
    }

    private static func describe(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        // Plist scalars bridge to NSNumber, so one branch covers Int, Double and
        // Bool without guessing the original Swift type.
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let data = value as? Data {
            return String(format: String(localized: "%lld bytes"), data.count)
        }
        if let dict = value as? [String: Any] {
            return String(format: String(localized: "%lld fields"), dict.count)
        }
        if let array = value as? [Any] {
            return String(format: String(localized: "%lld items"), array.count)
        }
        return String(describing: value)
    }
}
