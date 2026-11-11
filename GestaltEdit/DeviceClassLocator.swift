import Foundation
import MachO

/// Resolves the CacheData byte offset of `DeviceClassNumber`
/// (`mtrAoWJ3gsq+I90ZnQ0vQw`) by reading libMobileGestalt's own metadata instead
/// of guessing from a hex pattern. The offset moves between iOS builds, so a
/// pattern search can silently write the wrong nibble; this reads the real one.
enum DeviceClassLocator {
    static let cacheDataKey = "mtrAoWJ3gsq+I90ZnQ0vQw"

    private static let imagePath = "/usr/lib/libMobileGestalt.dylib"
    private static var didLookup = false
    private static var cachedOffset: Int?

    /// Byte offset inside CacheData, or nil when the library cannot be read.
    static func cacheDataOffset() -> Int? {
        if didLookup { return cachedOffset }
        didLookup = true
        cachedOffset = resolveOffset()
        return cachedOffset
    }

    /// Injectable for tests and for the nibble fallback path.
    static func resetCache() {
        didLookup = false
        cachedOffset = nil
    }

    private static func resolveOffset() -> Int? {
        guard let handle = dlopen(imagePath, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }

        var header: UnsafePointer<mach_header_64>?
        var slide = 0
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index),
                  String(cString: name) == imagePath,
                  let candidate = _dyld_get_image_header(index) else { continue }
            header = UnsafeRawPointer(candidate).assumingMemoryBound(to: mach_header_64.self)
            slide = _dyld_get_image_vmaddr_slide(index)
            break
        }
        guard let header else { return nil }

        var cstringAddress: UInt64 = 0
        var cstringSize: UInt64 = 0
        var constAddress: UInt64 = 0
        var constSize: UInt64 = 0

        var commandCursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<Int(header.pointee.ncmds) {
            let command = commandCursor.assumingMemoryBound(to: load_command.self)
            if command.pointee.cmd == LC_SEGMENT_64 {
                let segment = commandCursor.assumingMemoryBound(to: segment_command_64.self)
                // segname sits right after cmd/cmdsize (8 bytes), NUL-terminated.
                let segmentName = String(
                    cString: UnsafeRawPointer(segment).advanced(by: 8)
                        .assumingMemoryBound(to: CChar.self)
                )

                var sectionCursor = commandCursor.advanced(by: MemoryLayout<segment_command_64>.size)
                for _ in 0..<Int(segment.pointee.nsects) {
                    let section = sectionCursor.assumingMemoryBound(to: section_64.self)
                    // sectname is the first field of section_64.
                    let sectionName = String(
                        cString: UnsafeRawPointer(section)
                            .assumingMemoryBound(to: CChar.self)
                    )

                    if segmentName == "__TEXT", sectionName == "__cstring" {
                        cstringAddress = section.pointee.addr
                        cstringSize = section.pointee.size
                    }
                    if (segmentName == "__AUTH_CONST" || segmentName == "__DATA_CONST"),
                       sectionName == "__const" {
                        constAddress = section.pointee.addr
                        constSize = section.pointee.size
                    }
                    sectionCursor = sectionCursor.advanced(by: MemoryLayout<section_64>.size)
                }
            }
            commandCursor = commandCursor.advanced(by: Int(command.pointee.cmdsize))
        }

        guard cstringAddress != 0, constAddress != 0,
              let cstringBase = UnsafeRawPointer(bitPattern: Int(cstringAddress) + slide),
              let constBase = UnsafeRawPointer(bitPattern: Int(constAddress) + slide) else {
            return nil
        }

        var keyAddress: UnsafeRawPointer?
        var cursor: UInt64 = 0
        while cursor < cstringSize {
            let stringAddress = cstringBase.advanced(by: Int(cursor))
                .assumingMemoryBound(to: CChar.self)
            let value = String(cString: stringAddress)
            if value == cacheDataKey {
                keyAddress = UnsafeRawPointer(stringAddress)
                break
            }
            cursor += UInt64(value.utf8.count + 1)
        }
        guard let keyAddress else { return nil }

        var metadataAddress: UnsafeRawPointer?
        var slot = 0
        while slot < Int(constSize) / 8 {
            let candidate = constBase.advanced(by: slot * 8)
                .assumingMemoryBound(to: UnsafeRawPointer.self).pointee
            if candidate == keyAddress {
                metadataAddress = constBase.advanced(by: slot * 8)
                break
            }
            slot += 1
        }
        guard let metadataAddress else { return nil }

        let offset = metadataAddress.advanced(by: 0x9a).loadUnaligned(as: UInt32.self)
        guard offset > 0, offset < 4096 else { return nil }
        return Int(offset)
    }
}
