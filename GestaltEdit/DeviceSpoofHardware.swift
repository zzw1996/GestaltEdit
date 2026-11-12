import Foundation

/// Board code and hardware platform for models whose values are published by
/// upstream tools. Everything else stays identity-only: an unknown board code
/// would make the device report hardware it does not have.
enum DeviceSpoofHardware {
    static let known: [String: (hardware: String, cpu: String)] = [
        // iPhone
        "iPhone16,1": ("D83AP", "t8130"),
        "iPhone16,2": ("D84AP", "t8130"),
        "iPhone17,1": ("D93AP", "t8140"),
        "iPhone17,2": ("D94AP", "t8140"),
        "iPhone17,3": ("D47AP", "t8140"),
        "iPhone17,4": ("D48AP", "t8140"),
        "iPhone18,3": ("V57AP", "t8150"),
        // iPad (A17 Pro)
        "iPad16,1": ("J410AP", "t8130"),
        "iPad16,2": ("J411AP", "t8130"),
        // iPad Pro (M4)
        "iPad16,3": ("J717AP", "t8182"),
        "iPad16,4": ("J718AP", "t8182"),
        "iPad16,5": ("J720AP", "t8182"),
        "iPad16,6": ("J721AP", "t8182"),
        // iPad Pro (M2) and iPad Air (M2)
        "iPad14,3": ("J617AP", "t8112"),
        "iPad14,4": ("J618AP", "t8112"),
        "iPad14,5": ("J620AP", "t8112"),
        "iPad14,6": ("J621AP", "t8112"),
        "iPad14,8": ("J507AP", "t8112"),
        "iPad14,9": ("J508AP", "t8112"),
        "iPad14,10": ("J537AP", "t8112"),
        "iPad14,11": ("J538AP", "t8112"),
        // iPad Pro (M1) and iPad Air (M1)
        "iPad13,4": ("J517AP", "t8103"),
        "iPad13,5": ("J517xAP", "t8103"),
        "iPad13,8": ("J522AP", "t8103"),
        "iPad13,9": ("J522xAP", "t8103"),
        "iPad13,16": ("J407AP", "t8103"),
        "iPad13,17": ("J408AP", "t8103")
    ]

    static func hardware(for productType: String) -> (hardware: String, cpu: String)? {
        known[productType]
    }

    static var describedCount: Int { known.count }
}
