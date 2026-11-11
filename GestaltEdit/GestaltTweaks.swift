import Foundation

enum GestaltTweakCategory: String, CaseIterable, Identifiable {
    case region
    case display
    case hardware
    case ipad
    case internalFeatures

    var id: String { rawValue }

    var label: String {
        switch self {
        case .display: String(localized: "Display & Appearance")
        case .hardware: String(localized: "Hardware Capabilities")
        case .ipad: String(localized: "iPad Capabilities")
        case .region: String(localized: "Region")
        case .internalFeatures: String(localized: "Internal & Research")
        }
    }
}

/// The two supported ways to expose iPadOS multitasking on an iPhone.
enum IPadMode: String, Codable, CaseIterable, Identifiable {
    /// Device class stays iPhone; only the multitasking capability flags are set.
    /// Apps keep phone layouts.
    case capabilities
    /// Full iPadOS mode: device class becomes iPad, so apps adopt tablet layouts.
    case full

    var id: String { rawValue }
}

/// A reversible bookkeeping record of the `DeviceClassNumber` nibble we changed.
/// Keeping the offset and the original value is what makes the mode reversible:
/// CacheData is an undocumented byte blob, so nothing can be recomputed later.
struct IPadDeviceClassPatch: Codable, Equatable {
    let nibbleOffset: Int
    let originalNibble: String
}

/// What this app wrote for a given iPadOS mode, and what the fields looked like
/// before. Used to put the plist back exactly as it was.
struct IPadModeRecord: Codable, Equatable {
    let mode: IPadMode
    let patch: IPadDeviceClassPatch?
    let previousValues: [String: Int]
    /// Every field this app touched for the mode, accumulated across switches.
    let writtenKeys: [String]
}

enum GestaltTweakID: String, CaseIterable, Identifiable {
    case supportsDynamicIsland
    case bootChime
    case chargeLimit
    case tapToWake
    case cameraButton
    case disableParallax
    case enableLiquidGlassLowPerformance
    case disableLiquidGlassLowPerformance
    case stageManager
    case iPadApps
    case pencil
    case actionButton
    case internalInstall
    case internalStorage
    case securityResearchDevice
    case collisionSOS
    case alwaysOnDisplay
    case alwaysOnDisplayVibrancy

    var id: String { rawValue }
}

struct GestaltTweakDefinition: Identifiable {
    let id: GestaltTweakID
    let category: GestaltTweakCategory
    let title: String
    let detail: String
    let values: [String: Any]
    var isRisky = false
}

enum GestaltTweakCatalog {
    static let definitions: [GestaltTweakDefinition] = [
        .init(id: .supportsDynamicIsland, category: .display, title: String(localized: "Enable Dynamic Island Capability"), detail: String(localized: "Nugget's alternate enable method."), values: ["YlEtTtHlNesRBMal1CqRaA": 1]),
        .init(id: .alwaysOnDisplay, category: .display, title: String(localized: "Always-On Display"), detail: String(localized: "May increase burn-in risk on unsupported devices."), values: ["2OOJf1VhaM7NxfRok3HbWQ": 1, "j8/Omm6s1lsmTDFsXjsBfA": 1], isRisky: true),
        .init(id: .alwaysOnDisplayVibrancy, category: .display, title: String(localized: "AOD Vibrancy"), detail: String(localized: "Use this when AOD rendering looks incorrect."), values: ["ykpu7qyhqFweVMKtxNylWA": 1]),
        .init(id: .disableParallax, category: .display, title: String(localized: "Disable Wallpaper Parallax"), detail: String(localized: "Stops wallpaper motion based on device movement."), values: ["UIParallaxCapability": 0]),
        .init(id: .enableLiquidGlassLowPerformance, category: .display, title: String(localized: "Enable Liquid Glass Low-Performance Mode"), detail: String(localized: "For iOS 26 and later."), values: ["SAGvsp6O6kAQ4fEfDJpC4Q": 1]),
        .init(id: .disableLiquidGlassLowPerformance, category: .display, title: String(localized: "Disable Liquid Glass Low-Performance Mode"), detail: String(localized: "Mutually exclusive with the option above."), values: ["SAGvsp6O6kAQ4fEfDJpC4Q": 0]),

        .init(id: .bootChime, category: .hardware, title: String(localized: "Boot & Shutdown Chime"), detail: String(localized: "Enables the device boot and shutdown chime capability."), values: ["QHxt+hGLaBPbQJbXiUJX3w": 1]),
        .init(id: .chargeLimit, category: .hardware, title: String(localized: "Charge Limit Menu"), detail: String(localized: "Shows the Settings menu; actual limiting depends on hardware."), values: ["37NVydb//GP/GrhuTN+exg": 1]),
        .init(id: .tapToWake, category: .hardware, title: String(localized: "Tap to Wake"), detail: String(localized: "Primarily for models such as iPhone SE where it is unavailable."), values: ["yZf3GTRMGTuwSV/lD7Cagw": 1]),
        .init(id: .cameraButton, category: .hardware, title: String(localized: "iPhone 16 Camera Control Settings"), detail: String(localized: "Shows Camera Control settings and related capabilities."), values: ["CwvKxM2cEogD3p+HYgaW0Q": 1, "oOV1jhJbdV3AddkcCg0AEA": 1]),
        .init(id: .pencil, category: .hardware, title: String(localized: "Apple Pencil Settings"), detail: String(localized: "Shows the Apple Pencil settings page."), values: ["yhHcB0iH0d1XzPO/CFd3ow": 1]),
        .init(id: .actionButton, category: .hardware, title: String(localized: "Action Button Settings"), detail: String(localized: "Shows the Action Button settings page."), values: ["cT44WE1EohiwRzhsZ8xEsw": 1]),
        .init(id: .collisionSOS, category: .hardware, title: String(localized: "Collision SOS"), detail: String(localized: "Shows collision detection in SOS settings."), values: ["HCzWusHQwZDea6nNhaKndw": 1]),

        .init(id: .stageManager, category: .ipad, title: String(localized: "Stage Manager Support"), detail: String(localized: "Marks the device as supporting Stage Manager."), values: ["qeaj75wk3HF4DwQ8qbIi7g": 1]),
        .init(id: .iPadApps, category: .ipad, title: String(localized: "Allow iPad Apps"), detail: String(localized: "Enables iPad app compatibility types on iPhone."), values: ["9MZ5AdH43csAUajl/dU+IQ": [1, 2]]),

        .init(id: .internalInstall, category: .internalFeatures, title: String(localized: "Apple Internal Install"), detail: String(localized: "Enables internal capabilities such as Metal HUD; some services may misbehave."), values: ["EqrsVvjcYDdxHBiQmGhAWw": 1], isRisky: true),
        .init(id: .internalStorage, category: .internalFeatures, title: String(localized: "Internal Storage View"), detail: String(localized: "Shows internal files in Storage settings; high risk on some iPads."), values: ["LBJfwOEzExRxzlAnSuI7eg": 1], isRisky: true),
        .init(id: .securityResearchDevice, category: .internalFeatures, title: String(localized: "Security Research Device Mode"), detail: String(localized: "Marks the device as a Security Research Device."), values: ["XYlJKKkj2hztRP1NWWnhlw": 1], isRisky: true)
    ]

    static func definition(for id: GestaltTweakID) -> GestaltTweakDefinition? {
        definitions.first { $0.id == id }
    }
}

struct DynamicIslandOption: Identifiable, Hashable {
    let subtype: Int
    let title: String
    var id: Int { subtype }

    static let all: [DynamicIslandOption] = [
        .init(subtype: 2436, title: String(localized: "iPhone X Gestures (SE)")),
        .init(subtype: 2556, title: "iPhone 14 Pro"),
        .init(subtype: 2796, title: "iPhone 14 Pro Max"),
        .init(subtype: 2622, title: "iPhone 16 Pro"),
        .init(subtype: 2868, title: "iPhone 16 Pro Max"),
        .init(subtype: 2736, title: "iPhone Air")
    ]
}

enum GestaltTweakError: LocalizedError {
    case artworkDictionaryMissing
    case cacheDataMissing
    case cacheDataTooShort
    case cacheDataPatternNotFound
    case invalidCacheDataOffset
    case ipadModeNotRevertible

    var errorDescription: String? {
        switch self {
        case .artworkDictionaryMissing: String(localized: "MobileGestalt is missing the ArtworkDevice dictionary, so Dynamic Island or model name cannot be changed.")
        case .cacheDataMissing: String(localized: "MobileGestalt is missing CacheData, so iPadOS mode cannot be enabled.")
        case .cacheDataTooShort: String(localized: "CacheData is too short to apply iPadOS mode safely.")
        case .cacheDataPatternNotFound: String(localized: "The iPadOS marker required by Nugget was not found in CacheData.")
        case .invalidCacheDataOffset: String(localized: "CacheData marker validation failed. No changes were made.")
        case .ipadModeNotRevertible: String(localized: "This iPadOS mode was not applied by GestaltEdit, so it cannot be reverted here. Restore a backup instead.")
        }
    }
}

extension GestaltPlist {
    // "Device is an iPad". This is the identity flag: without it the system keeps
    // treating the phone as a phone and apps keep their phone layouts.
    static let ipadIdentityKey = "uKc7FPnEO++lVhHWHFlGbQ"
    // Stage Manager capability flag, independent of the device class.
    static let ipadStageManagerKey = "qeaj75wk3HF4DwQ8qbIi7g"
    // Medusa window capabilities: floating live apps, overlay apps, pinned apps
    // and PIP mirroring. These are capability flags, not an identity change.
    static let ipadMultitaskingKeys = [
        "mG0AnH/Vy1veoqoLRAIgTA",
        "UCG5MkVahJxG1YULbbd5Bg",
        "ZYqko/XM5zD3XBfN5RmaXA",
        "nVh/gwNpy7Jv1NOk00CMrw"
    ]

    static func keys(for mode: IPadMode) -> [String] {
        switch mode {
        case .capabilities: ipadMultitaskingKeys + [ipadStageManagerKey]
        case .full: ipadMultitaskingKeys + [ipadIdentityKey]
        }
    }

    /// Reads one CacheData nibble so the UI can show what the device class
    /// really holds instead of trusting the staged state.
    func deviceClassNibble(at index: Int) -> String? {
        guard let cacheData = dict["CacheData"] as? Data,
              index >= 0, index < cacheData.count * 2 else { return nil }
        let byte = cacheData[cacheData.startIndex + index / 2]
        let hex = String(format: "%02x", byte)
        return index % 2 == 0 ? String(hex.first!) : String(hex.last!)
    }

    /// Which mode the current file already carries, if any.
    var appliedIPadMode: IPadMode? {
        let values = cacheExtra
        if let identity = values[Self.ipadIdentityKey] as? Int, identity != 0 {
            return .full
        }
        let capabilities = Self.ipadMultitaskingKeys.allSatisfy { key in
            (values[key] as? Int) == 1
        }
        return capabilities ? .capabilities : nil
    }

    mutating func apply(definition: GestaltTweakDefinition) throws {
        for (key, value) in definition.values {
            setCacheExtra(value, forKey: key)
        }
    }

    /// Capability flags only. The device keeps reporting as an iPhone, so every
    /// app keeps its phone layout; whether iPadOS exposes the window UI on top of
    /// these flags depends on the system and has to be verified on-device.
    mutating func enableIPadCapabilities() {
        for key in Self.keys(for: .capabilities) {
            setCacheExtra(1, forKey: key)
        }
    }

    /// Full iPadOS mode: capability flags plus the iPad device class in CacheData.
    mutating func enableIPadMode() throws -> IPadDeviceClassPatch {
        for key in Self.ipadMultitaskingKeys {
            setCacheExtra(1, forKey: key)
        }
        setCacheExtra(1, forKey: Self.ipadIdentityKey)
        let result = try patchDeviceClassNumber(to: "3")
        return IPadDeviceClassPatch(nibbleOffset: result.offset, originalNibble: result.previous)
    }

    /// Puts back the flags and the device class nibble this app changed earlier.
    mutating func restoreIPadMode(using record: IPadModeRecord) throws {
        if let patch = record.patch {
            try restoreDeviceClassNumber(using: patch)
        }
        let keys = record.writtenKeys.isEmpty ? Self.keys(for: record.mode) : record.writtenKeys
        for key in keys {
            if let value = record.previousValues[key] {
                setCacheExtra(value, forKey: key)
            } else {
                removeCacheExtraValue(forKey: key)
            }
        }
    }

    mutating func setDynamicIslandSubtype(_ subtype: Int) throws {
        let key = "oPeik/9e8lQWMszEjbPzng"
        guard var artwork = cacheExtra[key] as? [String: Any] else {
            throw GestaltTweakError.artworkDictionaryMissing
        }
        artwork["ArtworkDeviceSubType"] = subtype
        setCacheExtra(artwork, forKey: key)
        setCacheExtra(1, forKey: "YlEtTtHlNesRBMal1CqRaA")
    }

    mutating func setModelName(_ name: String) throws {
        let key = "oPeik/9e8lQWMszEjbPzng"
        guard var artwork = cacheExtra[key] as? [String: Any] else {
            throw GestaltTweakError.artworkDictionaryMissing
        }
        artwork["ArtworkDeviceProductDescription"] = name
        setCacheExtra(artwork, forKey: key)
    }

    private static let deviceClassNumberSearchStart = 1616
    private static let deviceClassNumberSearchLength = 200

    /// Writes the device class nibble and reports what it used to be, so the
    /// change can be undone later without guessing again.
    private mutating func patchDeviceClassNumber(to newValue: String) throws -> (offset: Int, previous: String) {
        var nibbles = try Self.cacheDataNibbles(in: dict)
        let offset = try Self.deviceClassNumberOffset(in: nibbles)
        let leftOffset = offset - 67
        let rightOffset = offset + 13
        guard leftOffset > 0, rightOffset < nibbles.count - 1 else {
            throw GestaltTweakError.invalidCacheDataOffset
        }
        for position in [leftOffset, rightOffset] {
            guard ["1", "3"].contains(String(nibbles[position])),
                  nibbles[position - 1] == "0", nibbles[position + 1] == "0" else {
                throw GestaltTweakError.invalidCacheDataOffset
            }
        }
        let previous = String(nibbles[leftOffset])
        guard previous != newValue else { return (leftOffset, previous) }
        nibbles[leftOffset] = Character(newValue)
        try Self.writeCacheData(nibbles, to: &dict)
        return (leftOffset, previous)
    }

    /// Undoes `patchDeviceClassNumber(to:)` using the recorded offset instead of
    /// searching again, and refuses to write when the stored position no longer
    /// matches what this app wrote.
    private mutating func restoreDeviceClassNumber(using patch: IPadDeviceClassPatch) throws {
        var nibbles = try Self.cacheDataNibbles(in: dict)
        let offset = patch.nibbleOffset
        guard offset > 0, offset + 1 < nibbles.count,
              ["1", "3"].contains(patch.originalNibble) else {
            throw GestaltTweakError.invalidCacheDataOffset
        }
        if String(nibbles[offset]) == patch.originalNibble { return }
        guard String(nibbles[offset]) == "3",
              nibbles[offset - 1] == "0", nibbles[offset + 1] == "0" else {
            throw GestaltTweakError.invalidCacheDataOffset
        }
        nibbles[offset] = Character(patch.originalNibble)
        try Self.writeCacheData(nibbles, to: &dict)
    }

    private static func deviceClassNumberOffset(in nibbles: [Character]) throws -> Int {
        guard nibbles.count > deviceClassNumberSearchStart + 2 else {
            throw GestaltTweakError.cacheDataTooShort
        }
        let end = min(nibbles.count, deviceClassNumberSearchStart + deviceClassNumberSearchLength)
        let slice = String(nibbles[deviceClassNumberSearchStart..<end])
        let regex = try NSRegularExpression(pattern: "0+(?:5555)*([0-9a-f]{4})")
        let nsRange = NSRange(slice.startIndex..<slice.endIndex, in: slice)
        var matchedOffset: Int?
        regex.enumerateMatches(in: slice, range: nsRange) { match, _, stop in
            guard let range = match.flatMap({ Range($0.range(at: 1), in: slice) }) else { return }
            let value = slice[range]
            if value.filter({ $0 != "0" }).count >= 3 {
                matchedOffset = deviceClassNumberSearchStart
                    + slice.distance(from: slice.startIndex, to: range.lowerBound)
                stop.pointee = true
            }
        }
        guard let matchedOffset else { throw GestaltTweakError.cacheDataPatternNotFound }
        return matchedOffset
    }

    private static func cacheDataNibbles(in dict: [String: Any]) throws -> [Character] {
        guard let cacheData = dict["CacheData"] as? Data else {
            throw GestaltTweakError.cacheDataMissing
        }
        return cacheData.reduce(into: [Character]()) { nibbles, byte in
            nibbles.append(contentsOf: String(format: "%02x", byte))
        }
    }

    private static func writeCacheData(_ nibbles: [Character], to dict: inout [String: Any]) throws {
        let hex = String(nibbles)
        guard hex.count % 2 == 0 else { throw GestaltTweakError.invalidCacheDataOffset }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw GestaltTweakError.invalidCacheDataOffset
            }
            data.append(byte)
            index = next
        }
        dict["CacheData"] = data
    }
}
