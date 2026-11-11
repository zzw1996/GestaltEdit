import Foundation

// Run from the repository root:
// xcrun swiftc GestaltEdit/BackupChanges.swift Tests/BackupChanges/main.swift \
//   -o /tmp/backup-change-tests && /tmp/backup-change-tests

func checkAddedModifiedRemoved() {
    let old: [String: Any] = [
        "CacheExtra": ["a": 1, "b": 2],
        "Other": "keep"
    ]
    let new: [String: Any] = [
        "CacheExtra": ["a": 1, "b": 3, "c": 1],
        "Other": "keep"
    ]
    let set = GestaltChangeDiff.changes(old: old, new: new, source: .tweaks)

    precondition(set.added == 1, "expected one added field")
    precondition(set.modified == 1, "expected one modified field")
    precondition(set.removed == 0, "expected no removed field")
    precondition(set.total == 2)
    precondition(!set.truncated)

    precondition(set.changes.contains { change in
        change.key == "CacheExtra/c" && change.oldValue == nil && change.newValue == "1"
    }, "added field must carry its new value only")

    precondition(set.changes.contains { change in
        change.key == "CacheExtra/b" && change.oldValue == "2" && change.newValue == "3"
    }, "modified field must carry both values")

    precondition(!set.changes.contains { $0.key == "Other" }, "unchanged fields must not be listed")
}

func checkRemovedField() {
    let old: [String: Any] = ["CacheExtra": ["keep": 1, "gone": 0]]
    let new: [String: Any] = ["CacheExtra": ["keep": 1]]
    let set = GestaltChangeDiff.changes(old: old, new: new, source: .fieldEditor)

    precondition(set.removed == 1)
    precondition(set.changes.first?.key == "CacheExtra/gone")
    precondition(set.changes.first?.newValue == nil)
}

func checkCacheDataBytesCompared() {
    let old: [String: Any] = ["CacheData": Data([0x01, 0x02])]
    let new: [String: Any] = ["CacheData": Data([0x01, 0x03])]
    let set = GestaltChangeDiff.changes(old: old, new: new, source: .restore)

    precondition(set.modified == 1, "CacheData bytes must be compared, not just lengths")

    let sameOld: [String: Any] = ["CacheData": Data([0x01, 0x03])]
    let sameSet = GestaltChangeDiff.changes(old: sameOld, new: new, source: .restore)
    precondition(sameSet.total == 0, "identical CacheData must not be reported")
}

func checkTruncation() {
    var old: [String: Any] = [:]
    var new: [String: Any] = [:]
    for index in 0..<(GestaltChangeDiff.limit * 2) {
        old["k\(index)"] = 0
        new["k\(index)"] = 1
    }
    let set = GestaltChangeDiff.changes(old: old, new: new, source: .automation)
    precondition(set.modified == GestaltChangeDiff.limit * 2)
    precondition(set.changes.count == GestaltChangeDiff.limit)
    precondition(set.truncated)
}

func checkCoding() {
    let set = GestaltChangeDiff.changes(
        old: ["CacheExtra": ["q": 1]],
        new: ["CacheExtra": ["q": 2]],
        source: .tweaks
    )
    guard let data = try? JSONEncoder().encode(set),
          let decoded = try? JSONDecoder().decode(BackupChangeSet.self, from: data) else {
        fatalError("Change set did not survive a JSON round trip")
    }
    precondition(decoded == set)
    precondition(decoded.changes.first?.detail == "1 → 2")
}

checkAddedModifiedRemoved()
checkRemovedField()
checkCacheDataBytesCompared()
checkTruncation()
checkCoding()

print("Passed: backup change diff, truncation and coding.")
