import Foundation

/// Plain-language knowledge about the obfuscated MobileGestalt keys, so the
/// field editor shows what a key does instead of a bare hash.
enum GestaltKeyCategory: String, CaseIterable, Identifiable {
    case identity
    case display
    case hardware
    case multitasking
    case security
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identity: String(localized: "Device Identity")
        case .display: String(localized: "Display & Appearance")
        case .hardware: String(localized: "Hardware & Features")
        case .multitasking: String(localized: "Multitasking & Windows")
        case .security: String(localized: "Security & Debug")
        case .other: String(localized: "Other Fields")
        }
    }
}

enum GestaltKeyRisk: String {
    case safe
    case caution
    case risky

    var title: String {
        switch self {
        case .safe: String(localized: "Safe to change")
        case .caution: String(localized: "Change with care")
        case .risky: String(localized: "Risky")
        }
    }
}

struct GestaltKeyInfo {
    let key: String
    let title: String
    let summary: String
    let category: GestaltKeyCategory
    let risk: GestaltKeyRisk
}

enum GestaltKeyCatalog {
    static let entries: [String: GestaltKeyInfo] = {
        var map: [String: GestaltKeyInfo] = [:]
        for info in all {
            map[info.key] = info
        }
        return map
    }()

    static func info(for key: String) -> GestaltKeyInfo? {
        entries[key]
    }

    static func category(for key: String) -> GestaltKeyCategory {
        entries[key]?.category ?? .other
    }

    /// Known keys first, unknown keys after, both alphabetical inside a group.
    static func sortKey(_ key: String) -> String {
        let known = entries[key] != nil ? "0" : "1"
        return known + (info(for: key)?.title ?? key)
    }

    private static let all: [GestaltKeyInfo] = [
        // Identity
        .init(
            key: "mtrAoWJ3gsq+I90ZnQ0vQw",
            title: String(localized: "Device class number"),
            summary: String(localized: "Stored inside CacheData as an 8-byte number: 1 means iPhone, 3 means iPad. This is what makes apps choose phone or tablet layouts, and what iPadOS window features depend on."),
            category: .identity,
            risk: .risky
        ),
        .init(
            key: GestaltPlist.ipadIdentityKey,
            title: String(localized: "iPad identity flag"),
            summary: String(localized: "Tells the system this device is an iPad. iPad-only capabilities stay hidden until this flag exists, and it is normally paired with the iPad device class number."),
            category: .identity,
            risk: .risky
        ),
        .init(
            key: "9MZ5AdH43csAUajl/dU+IQ",
            title: String(localized: "iPad app compatibility"),
            summary: String(localized: "Lists the iPad app compatibility types ([1, 2]) and lets iPad apps be installed and opened on this device."),
            category: .identity,
            risk: .caution
        ),

        // Multitasking
        .init(
            key: GestaltPlist.ipadStageManagerKey,
            title: String(localized: "Stage Manager capability"),
            summary: String(localized: "Marks the device as capable of Stage Manager. It is only a capability flag: the window UI still needs the iPad device class."),
            category: .multitasking,
            risk: .caution
        ),
        .init(
            key: "mG0AnH/Vy1veoqoLRAIgTA",
            title: String(localized: "Medusa floating live apps"),
            summary: String(localized: "Capability flag for floating live app windows. Verified on-device to do nothing on its own."),
            category: .multitasking,
            risk: .safe
        ),
        .init(
            key: "UCG5MkVahJxG1YULbbd5Bg",
            title: String(localized: "Medusa overlay apps"),
            summary: String(localized: "Capability flag for overlay app windows. Verified on-device to do nothing on its own."),
            category: .multitasking,
            risk: .safe
        ),
        .init(
            key: "ZYqko/XM5zD3XBfN5RmaXA",
            title: String(localized: "Medusa pinned apps"),
            summary: String(localized: "Capability flag for pinned app windows. Verified on-device to do nothing on its own."),
            category: .multitasking,
            risk: .safe
        ),
        .init(
            key: "nVh/gwNpy7Jv1NOk00CMrw",
            title: String(localized: "Medusa PIP mirroring"),
            summary: String(localized: "Capability flag for mirroring a window into Picture-in-Picture. Verified on-device to do nothing on its own."),
            category: .multitasking,
            risk: .safe
        ),

        // Display
        .init(
            key: "YlEtTtHlNesRBMal1CqRaA",
            title: String(localized: "Dynamic Island capability"),
            summary: String(localized: "Marks the device as having the Dynamic Island. It only takes effect together with a matching artwork subtype."),
            category: .display,
            risk: .caution
        ),
        .init(
            key: "oPeik/9e8lQWMszEjbPzng",
            title: String(localized: "Artwork dictionary"),
            summary: String(localized: "A nested dictionary with the model description (ArtworkDeviceProductDescription) and the screen subtype (ArtworkDeviceSubType) used for Dynamic Island and the model name shown in Settings."),
            category: .display,
            risk: .caution
        ),
        .init(
            key: "UIParallaxCapability",
            title: String(localized: "Wallpaper parallax"),
            summary: String(localized: "Set to 0 to stop the wallpaper from shifting with device motion; 1 (or absent) keeps the effect."),
            category: .display,
            risk: .safe
        ),
        .init(
            key: "SAGvsp6O6kAQ4fEfDJpC4Q",
            title: String(localized: "Liquid Glass low-performance mode"),
            summary: String(localized: "iOS 26 rendering switch: 1 forces the cheaper Liquid Glass path, 0 forces the full one."),
            category: .display,
            risk: .safe
        ),
        .init(
            key: "2OOJf1VhaM7NxfRok3HbWQ",
            title: String(localized: "Always-On Display (part 1)"),
            summary: String(localized: "One half of the Always-On Display enable pair. Both this and j8/Omm6s1lsmTDFsXjsBfA must be set."),
            category: .display,
            risk: .risky
        ),
        .init(
            key: "j8/Omm6s1lsmTDFsXjsBfA",
            title: String(localized: "Always-On Display (part 2)"),
            summary: String(localized: "Second half of the Always-On Display enable pair; it is useless without 2OOJf1VhaM7NxfRok3HbWQ."),
            category: .display,
            risk: .risky
        ),
        .init(
            key: "ykpu7qyhqFweVMKtxNylWA",
            title: String(localized: "AOD vibrancy"),
            summary: String(localized: "Changes how Always-On Display renders brightness and colour; use it when the AOD looks wrong."),
            category: .display,
            risk: .caution
        ),

        // Hardware
        .init(
            key: "QHxt+hGLaBPbQJbXiUJX3w",
            title: String(localized: "Boot & shutdown chime"),
            summary: String(localized: "Capability flag that enables the startup and shutdown sound."),
            category: .hardware,
            risk: .caution
        ),
        .init(
            key: "37NVydb//GP/GrhuTN+exg",
            title: String(localized: "Charge limit menu"),
            summary: String(localized: "Shows the 80% charge limit menu in Settings; real limiting still depends on hardware support."),
            category: .hardware,
            risk: .caution
        ),
        .init(
            key: "yZf3GTRMGTuwSV/lD7Cagw",
            title: String(localized: "Tap to Wake"),
            summary: String(localized: "Capability flag for waking the screen with a tap, mainly useful on models that lack it."),
            category: .hardware,
            risk: .caution
        ),
        .init(
            key: "CwvKxM2cEogD3p+HYgaW0Q",
            title: String(localized: "Camera Control settings"),
            summary: String(localized: "Shows the Camera Control settings page; paired with the capability flag below."),
            category: .hardware,
            risk: .caution
        ),
        .init(
            key: "oOV1jhJbdV3AddkcCg0AEA",
            title: String(localized: "Camera Control capability"),
            summary: String(localized: "Capability flag for the hardware Camera Control button."),
            category: .hardware,
            risk: .caution
        ),
        .init(
            key: "yhHcB0iH0d1XzPO/CFd3ow",
            title: String(localized: "Apple Pencil settings"),
            summary: String(localized: "Shows the Apple Pencil settings page."),
            category: .hardware,
            risk: .caution
        ),
        .init(
            key: "cT44WE1EohiwRzhsZ8xEsw",
            title: String(localized: "Action Button settings"),
            summary: String(localized: "Shows the Action Button settings page."),
            category: .hardware,
            risk: .caution
        ),
        .init(
            key: "HCzWusHQwZDea6nNhaKndw",
            title: String(localized: "Collision SOS"),
            summary: String(localized: "Shows collision detection in the SOS settings; the hardware must exist for it to work."),
            category: .hardware,
            risk: .caution
        ),

        // Security
        .init(
            key: "EqrsVvjcYDdxHBiQmGhAWw",
            title: String(localized: "Apple internal install"),
            summary: String(localized: "Marks the device as an internal Apple build, which exposes tools such as the Metal HUD. Some system services can misbehave."),
            category: .security,
            risk: .risky
        ),
        .init(
            key: "LBJfwOEzExRxzlAnSuI7eg",
            title: String(localized: "Internal storage view"),
            summary: String(localized: "Shows internal files in the Storage settings. Reported to cause problems on some iPads."),
            category: .security,
            risk: .risky
        ),
        .init(
            key: "XYlJKKkj2hztRP1NWWnhlw",
            title: String(localized: "Security research device"),
            summary: String(localized: "Marks the device as a Security Research Device, which relaxes several system restrictions."),
            category: .security,
            risk: .risky
        ),

        // Top level
        .init(
            key: "CacheExtra",
            title: String(localized: "CacheExtra dictionary"),
            summary: String(localized: "The override dictionary the system reads before hardware defaults. Most edits in this app land here."),
            category: .other,
            risk: .safe
        ),
        .init(
            key: "CacheData",
            title: String(localized: "CacheData blob"),
            summary: String(localized: "An opaque byte blob for values that cannot be written as normal fields, including the device class number. Editing it by hand is not supported."),
            category: .other,
            risk: .risky
        ),
        .init(
            key: "CacheUUID",
            title: String(localized: "Cache UUID"),
            summary: String(localized: "Identifier of this cache file. Leave it untouched."),
            category: .other,
            risk: .safe
        ),
        .init(
            key: "CacheVersion",
            title: String(localized: "Cache version"),
            summary: String(localized: "Version stamp written by the system. Leave it untouched."),
            category: .other,
            risk: .safe
        )
    ]
}
