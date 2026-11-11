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

func checkDeviceClassBytes() throws {
    var plist = GestaltPlist(dict: ["CacheData": Data([1, 0, 0, 0, 0, 0, 0, 0, 0x02])])
    precondition(plist.deviceClassValue(at: 0) == 1)
    try plist.setDeviceClassValue(3, at: 0)
    precondition(plist.deviceClassValue(at: 0) == 3)
    precondition(plist.deviceClassNibble(at: 0) == "0")
    precondition(plist.deviceClassNibble(at: 1) == "3")

    let patch = IPadDeviceClassPatch(nibbleOffset: 0, originalNibble: "1", byteOffset: 0, originalValue: 1)
    precondition(plist.deviceClassMatches(patch))
    precondition(plist.deviceClassValue(at: 5) == nil)
}

func checkLegacyRecordDecoding() {
    let legacy = """
    {"mode":"full","patch":{"nibbleOffset":611,"originalNibble":"1"},"previousValues":{},"writtenKeys":[]}
    """
    guard let data = legacy.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(IPadModeRecord.self, from: data) else {
        fatalError("Legacy record did not decode")
    }
    precondition(decoded.patch?.byteOffset == nil)
    precondition(decoded.patch?.originalValue == nil)
}

func checkByteOffsetRestore() throws {
    var plist = GestaltPlist(dict: ["CacheData": Data([3, 0, 0, 0, 0, 0, 0, 0])])
    let record = IPadModeRecord(
        mode: .full,
        patch: IPadDeviceClassPatch(nibbleOffset: 0, originalNibble: "1", byteOffset: 0, originalValue: 1),
        previousValues: [:],
        writtenKeys: GestaltPlist.keys(for: .full)
    )
    try plist.restoreIPadMode(using: record)
    precondition(plist.deviceClassValue(at: 0) == 1)
}

func checkTweakStateAndRevert() throws {
    guard let definition = GestaltTweakCatalog.definition(for: .bootChime) else {
        fatalError("Boot chime definition missing")
    }
    let key = "QHxt+hGLaBPbQJbXiUJX3w"

    var plist = GestaltPlist(dict: ["CacheExtra": [key: 0]])
    precondition(!plist.matches(definition: definition))
    try plist.apply(definition: definition)
    precondition(plist.matches(definition: definition))

    // A recorded original value is written back verbatim.
    plist.revert(definition: definition, originals: [key: 0])
    precondition((plist.cacheExtra[key] as? Int) == 0)
    precondition(!plist.matches(definition: definition))

    // With no recorded original the key is removed, so the system default applies.
    var fresh = GestaltPlist(dict: ["CacheExtra": [:]])
    try fresh.apply(definition: definition)
    fresh.revert(definition: definition, originals: [:])
    precondition(fresh.cacheExtra[key] == nil)

    // A definition with a non-integer expected value (iPad app compatibility) must
    // still be detected through the array comparison path.
    guard let ipadApps = GestaltTweakCatalog.definition(for: .iPadApps) else {
        fatalError("iPad apps definition missing")
    }
    var apps = GestaltPlist(dict: ["CacheExtra": ["9MZ5AdH43csAUajl/dU+IQ": [1, 2]]])
    precondition(apps.matches(definition: ipadApps))
    apps.setCacheExtra([1], forKey: "9MZ5AdH43csAUajl/dU+IQ")
    precondition(!apps.matches(definition: ipadApps))
}

checkModeKeys()
checkDetection()
checkRecordCoding()
checkRestoreWithoutCacheDataFails()
checkCapabilityFlagsAreWritten()
checkNibbleAccessor()
try checkDeviceClassBytes()
checkLegacyRecordDecoding()
try checkByteOffsetRestore()
try checkTweakStateAndRevert()

print("Passed: iPad mode keys, detection, record coding, restore guards, capability writes, nibble reads, exact device-class writes and tweak state/revert.")
