import Foundation

struct GestaltBackup: Identifiable, Hashable {
    let url: URL
    let createdAt: Date
    let byteCount: Int64
    /// What was written right after this snapshot, when the app knows it.
    let changes: BackupChangeSet?
    /// Created or imported by the user; never pruned automatically.
    let isManual: Bool

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum GestaltBackupStore {
    /// How many automatic snapshots to keep. Manual backups are never pruned.
    static let automaticRetention = 20

    static func create(from data: Data, manual: Bool = false) throws -> GestaltBackup {
        let directory = try backupDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let url = directory
            .appendingPathComponent("MobileGestalt_\(formatter.string(from: Date()))")
            .appendingPathExtension("plist")
        try data.write(to: url, options: .atomic)
        if manual {
            markManual(url)
        } else {
            pruneAutomaticBackups()
        }
        return try metadata(for: url)
    }

    /// A manual snapshot the user created or imported; kept until deleted.
    static func isManual(_ backup: GestaltBackup) -> Bool {
        FileManager.default.fileExists(atPath: manualMarker(for: backup.url).path)
    }

    private static func markManual(_ url: URL) {
        let marker = manualMarker(for: url)
        if !FileManager.default.fileExists(atPath: marker.path) {
            FileManager.default.createFile(atPath: marker.path, contents: Data())
        }
    }

    private static func manualMarker(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("plist.manual")
    }

    /// Keeps the newest automatic snapshots and drops the rest. Manual snapshots
    /// are skipped so a deliberate backup never disappears on its own.
    private static func pruneAutomaticBackups() {
        guard let all = try? list() else { return }
        let automatic = all.filter { !isManual($0) }
        guard automatic.count > automaticRetention else { return }
        for backup in automatic.dropFirst(automaticRetention) {
            try? delete(backup)
        }
    }

    static func list() throws -> [GestaltBackup] {
        let directory = try backupDirectory()
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "plist" }
        .map { try metadata(for: $0) }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func data(for backup: GestaltBackup) throws -> Data {
        try Data(contentsOf: backup.url)
    }

    static func delete(_ backup: GestaltBackup) throws {
        try FileManager.default.removeItem(at: backup.url)
        try? FileManager.default.removeItem(at: sidecarURL(for: backup.url))
        try? FileManager.default.removeItem(at: manualMarker(for: backup.url))
    }

    /// Records which fields the write that followed this snapshot changed.
    static func attach(_ changes: BackupChangeSet, to backup: GestaltBackup) throws {
        let data = try JSONEncoder().encode(changes)
        try data.write(to: sidecarURL(for: backup.url), options: .atomic)
    }

    /// The change log that travels with a backup, if one was recorded.
    static func changeLogURL(for backup: GestaltBackup) -> URL? {
        let url = sidecarURL(for: backup.url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func backupDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent("MobileGestalt Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func metadata(for url: URL) throws -> GestaltBackup {
        let values = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        return GestaltBackup(
            url: url,
            createdAt: values.creationDate ?? .distantPast,
            byteCount: Int64(values.fileSize ?? 0),
            changes: changes(for: url),
            isManual: FileManager.default.fileExists(atPath: manualMarker(for: url).path)
        )
    }

    private static func sidecarURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("changes.json")
    }

    private static func changes(for url: URL) -> BackupChangeSet? {
        guard let data = try? Data(contentsOf: sidecarURL(for: url)) else { return nil }
        return try? JSONDecoder().decode(BackupChangeSet.self, from: data)
    }
}
