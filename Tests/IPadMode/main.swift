import Foundation

// Run from the repository root:
// xcrun swiftc GestaltEdit/GestaltModels.swift GestaltEdit/GestaltTweaks.swift \
//   Tests/IPadMode/main.swift -o /tmp/ipad-mode-tests && /tmp/ipad-mode-tests

func checkModeKeys() {
    precondition(
        GestaltPlist.keys(for: .full)
            == GestaltPlist.ipadMultitaskingKeys + [GestaltPlist.ipadIdentityKey]
    )
    precondition(
        GestaltPlist.keys(for: .capabilities)
            == GestaltPlist.ipadMultitaskingKeys + [GestaltPlist.ipadStageManagerKey]
    )
}

func checkDetection() {
    var plist = GestaltPlist(dict: [:])
    precondition(plist.appliedIPadMode == nil)

    plist.enableIPadCapabilities()
    precondition(plist.appliedIPadMode == .capabilities)

    // Stage Manager alone, or identity alone, must not be confused with a mode.
    let stageManagerOnly = GestaltPlist(dict: [
        "CacheExtra": [GestaltPlist.ipadStageManagerKey: 1]
    ])
    precondition(stageManagerOnly.appliedIPadMode == nil)

    let identityOnly = GestaltPlist(dict: [
        "CacheExtra": [GestaltPlist.ipadIdentityKey: 1]
    ])
    precondition(identityOnly.appliedIPadMode == .full)
}

func checkRecordCoding() {
    let record = IPadModeRecord(
        mode: .full,
        patch: IPadDeviceClassPatch(nibbleOffset: 611, originalNibble: "1"),
        previousValues: [GestaltPlist.ipadStageManagerKey: 1],
        writtenKeys: GestaltPlist.keys(for: .full)
    )
    guard let data = try? JSONEncoder().encode(record),
          let decoded = try? JSONDecoder().decode(IPadModeRecord.self, from: data) else {
        fatalError("Record did not survive a JSON round trip")
    }
    precondition(decoded == record)
}

func checkRestoreWithoutCacheDataFails() {
    var plist = GestaltPlist(dict: [
        "CacheExtra": [GestaltPlist.ipadIdentityKey: 1]
    ])
    let record = IPadModeRecord(
        mode: .full,
        patch: IPadDeviceClassPatch(nibbleOffset: 611, originalNibble: "1"),
        previousValues: [:],
        writtenKeys: GestaltPlist.keys(for: .full)
    )
    do {
        try plist.restoreIPadMode(using: record)
        preconditionFailure("Restoring without CacheData must fail")
    } catch GestaltTweakError.cacheDataMissing {
        // Expected: the file has no CacheData to put back.
    } catch {
        preconditionFailure("Unexpected error: \(error)")
    }
}

func checkCapabilityFlagsAreWritten() {
    var plist = GestaltPlist(dict: [:])
    plist.enableIPadCapabilities()
    let values = plist.cacheExtra
    for key in GestaltPlist.keys(for: .capabilities) {
        precondition(values[key] as? Int == 1)
    }
}

func checkNibbleAccessor() {
    let plist = GestaltPlist(dict: ["CacheData": Data([0x12, 0x34])])
    precondition(plist.deviceClassNibble(at: 0) == "1")
    precondition(plist.deviceClassNibble(at: 1) == "2")
    precondition(plist.deviceClassNibble(at: 2) == "3")
    precondition(plist.deviceClassNibble(at: 3) == "4")
    precondition(plist.deviceClassNibble(at: 4) == nil)
    precondition(GestaltPlist(dict: [:]).deviceClassNibble(at: 0) == nil)
}

checkModeKeys()
checkDetection()
checkRecordCoding()
checkRestoreWithoutCacheDataFails()
checkCapabilityFlagsAreWritten()
checkNibbleAccessor()

print("Passed: iPad mode keys, detection, record coding, restore guard, capability writes and nibble reads.")
