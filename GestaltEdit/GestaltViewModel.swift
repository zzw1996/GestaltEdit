import Combine
import Foundation

enum IPadModeChoice: Hashable, Identifiable {
    case off
    case capabilities
    case full

    var id: String { String(describing: self) }
}

/// What the file actually contains right now, shown in the diagnostics section.
struct IPadStatusSnapshot {
    let mode: IPadModeChoice
    let hasIdentity: Bool
    let stageManagerEnabled: Bool
    let capabilityCount: Int
    let deviceClassNibble: String?
    let deviceClassValue: UInt64?
    let resolvedOffset: Int?
    let recordedPatch: IPadDeviceClassPatch?
}

/// Key-level changes shown to the user before anything is written.
struct WritePreview: Identifiable {
    let id = UUID()
    let source: BackupChangeSource
    let changeSet: BackupChangeSet
    let riskyItems: [String]
}

/// A write that has been prepared but is waiting for confirmation.
struct PendingWrite {
    let plist: GestaltPlist
    let expectedAIRegion: AIRegionConfiguration?
    let source: BackupChangeSource
    let validation: ((GestaltPlist) throws -> Void)?
    let completion: (() -> Void)?
}

/// Values the identity panel shows; `nil` means the key is absent from the file.
struct DeviceIdentityView {
    let realProductType: String?
    let mgProductType: String?
    let hardwareModel: String?
    let cpuModel: String?
    let regulatoryModel: String?
    let hasSpoofFlags: Bool
    let snapshotDate: Date?
}

@MainActor
final class GestaltViewModel: ObservableObject {
    @Published var plist: GestaltPlist?
    @Published var isDirty = false
    @Published var isBusy = false
    @Published var notice: GestaltNotice?
    @Published private(set) var hasAttemptedLoad = false
    @Published private(set) var backups: [GestaltBackup] = []
    @Published var tweakOverrides: [GestaltTweakID: Bool] = [:]
    @Published var dynamicIslandSubtype: Int?
    @Published var changesModelName = false
    @Published var modelName = ""
    @Published var stagesAIRegion = false
    @Published var stagedIPadMode: IPadModeChoice?
    @Published private(set) var isRespringing = false
    @Published var writePreview: WritePreview?
    @Published private(set) var lastAutoBackupName: String?
    @Published private(set) var customPresets: [CustomPreset] = []

    private let access = GestaltAccess.shared()
    private var pendingWrite: PendingWrite?
    private var respringTimeout: Task<Void, Never>?
    /// What the file on disk held when it was last read, used to diff staged edits.
    private var baselineDictionary: [String: Any] = [:]
    private static let lastAutoBackupKey = "LastAutoBackupName"

    init() {
        lastAutoBackupName = UserDefaults.standard.string(forKey: Self.lastAutoBackupKey)
        customPresets = CustomPresetStore.list()
    }

    var aiRegionProfile: AIRegionProfile? {
        plist.flatMap(AIRegionProfile.init(plist:))
    }

    var requiresForcedAIEnable: Bool {
        plist != nil && aiRegionProfile == nil
    }

    var isAIRegionConfigured: Bool {
        guard let profile = aiRegionProfile,
              let cacheExtra = plist?.cacheExtra else { return false }
        return cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "LL"
            && cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] as? String == "LL/A"
            && cacheExtra["97JDvERpVwO+GHtthIh7hA"] as? String == profile.regulatoryModel
    }

    var hasStagedTweaks: Bool {
        !tweakOverrides.isEmpty
            || dynamicIslandSubtype != nil
            || (changesModelName && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || stagesAIRegion
            || stagedIPadMode != nil
    }

    var stagedChangeCount: Int {
        tweakOverrides.count
            + (dynamicIslandSubtype == nil ? 0 : 1)
            + (changesModelName ? 1 : 0)
            + (stagesAIRegion ? 1 : 0)
            + (stagedIPadMode == nil ? 0 : 1)
    }

    /// True when every key of this tweak already holds the value it writes.
    /// This is the on-disk truth, not anything the UI has staged.
    func isApplied(_ id: GestaltTweakID) -> Bool {
        guard let plist, let definition = GestaltTweakCatalog.definition(for: id) else { return false }
        return plist.matches(definition: definition)
    }

    /// Toggle position: staged intent first, otherwise the real file state.
    func desiredState(for id: GestaltTweakID) -> Bool {
        tweakOverrides[id] ?? isApplied(id)
    }

    var appliedTweakCount: Int {
        GestaltTweakCatalog.definitions.filter { isApplied($0.id) }.count
    }

    /// Number of tweaks whose staged state differs from the file.
    var pendingTweakChangeCount: Int {
        GestaltTweakCatalog.definitions.filter { definition in
            guard let desired = tweakOverrides[definition.id] else { return false }
            return desired != isApplied(definition.id)
        }.count
    }

    // MARK: - Custom presets

    /// Saves the tweaks the file currently has applied under a user-chosen name.
    @discardableResult
    func saveCurrentAsPreset(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ids = GestaltTweakCatalog.definitions
            .filter { isApplied($0.id) }
            .map { $0.id.rawValue }
        guard !ids.isEmpty else {
            notice = GestaltNotice(
                kind: .info,
                message: String(localized: "No applied tweaks yet, so there is nothing to save as a preset.")
            )
            return false
        }
        let preset = CustomPreset(id: UUID(), name: trimmed, tweakIDs: ids, createdAt: Date())
        customPresets.insert(preset, at: 0)
        CustomPresetStore.save(customPresets)
        return true
    }

    /// Stages everything the preset needs; already-applied tweaks stay untouched.
    func applyPreset(_ preset: CustomPreset) {
        tweakOverrides.removeAll()
        for raw in preset.tweakIDs {
            guard let id = GestaltTweakID(rawValue: raw), !isApplied(id) else { continue }
            tweakOverrides[id] = true
        }
        if tweakOverrides.isEmpty {
            notice = GestaltNotice(
                kind: .info,
                message: String(localized: "Everything in this preset is already applied.")
            )
        }
    }

    func deletePreset(_ preset: CustomPreset) {
        customPresets.removeAll { $0.id == preset.id }
        CustomPresetStore.save(customPresets)
    }

    /// Pretty-printed JSON so presets survive reinstalling the app.
    var presetExportJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(customPresets),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    /// Imports presets from JSON text pasted by the user. Existing names win, so
    /// a re-import cannot silently duplicate or overwrite a saved preset.
    @discardableResult
    func importPresets(fromJSON text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let presets = try? JSONDecoder().decode([CustomPreset].self, from: data) else {
            notice = GestaltNotice(
                kind: .error,
                message: String(localized: "That text is not a valid preset JSON file.")
            )
            return false
        }
        var added = 0
        for preset in presets where !preset.name.isEmpty {
            guard !customPresets.contains(where: { $0.name == preset.name }) else { continue }
            customPresets.append(
                CustomPreset(id: UUID(), name: preset.name, tweakIDs: preset.tweakIDs, createdAt: Date())
            )
            added += 1
        }
        guard added > 0 else {
            notice = GestaltNotice(
                kind: .info,
                message: String(localized: "Nothing new to import; preset names already exist.")
            )
            return false
        }
        customPresets = customPresets.sorted { $0.createdAt > $1.createdAt }
        CustomPresetStore.save(customPresets)
        return true
    }

    /// Read-only view of the region keys, so the user can verify what is on disk
    /// without opening the field editor.
    var regionSnapshot: (code: String, info: String, regulatory: String, device: String) {
        let values = plist?.cacheExtra ?? [:]
        return (
            values["h63QSdBCiT/z0WU6rdQv6Q"] as? String ?? "—",
            values["yK+xavymRGZ3xWc1tb8XDg"] as? String ?? "—",
            values["97JDvERpVwO+GHtthIh7hA"] as? String ?? "—",
            aiRegionProfile?.marketingName ?? String(localized: "Unknown")
        )
    }

    /// What the file currently carries, independent of anything staged.
    var currentIPadMode: IPadModeChoice {
        guard let mode = plist?.appliedIPadMode else { return .off }
        return mode == .full ? .full : .capabilities
    }

    func setIPadMode(_ choice: IPadModeChoice) {
        // Capabilities-only is no longer offered, but a stale flag set from an
        // earlier build must still be clearable through Off.
        if currentIPadMode == .capabilities {
            stagedIPadMode = choice == .off ? .off : choice
            return
        }
        stagedIPadMode = choice == currentIPadMode ? nil : choice
    }

    var ipadStatus: IPadStatusSnapshot {
        let values = plist?.cacheExtra ?? [:]
        let identity = (values[GestaltPlist.ipadIdentityKey] as? Int).map { $0 != 0 } ?? false
        let stageManager = (values[GestaltPlist.ipadStageManagerKey] as? Int) == 1
        let capabilityCount = GestaltPlist.ipadMultitaskingKeys.filter { key in
            (values[key] as? Int) == 1
        }.count
        let patch = IPadModeStore.load()?.patch
        let nibble = patch.flatMap { plist?.deviceClassNibble(at: $0.nibbleOffset) }
        let resolvedOffset = DeviceClassLocator.cacheDataOffset()
        let value = resolvedOffset.flatMap { plist?.deviceClassValue(at: $0) }
        return IPadStatusSnapshot(
            mode: currentIPadMode,
            hasIdentity: identity,
            stageManagerEnabled: stageManager,
            capabilityCount: capabilityCount,
            deviceClassNibble: nibble,
            deviceClassValue: value,
            resolvedOffset: resolvedOffset,
            recordedPatch: patch
        )
    }

    func load() {
        guard !isBusy else { return }
        hasAttemptedLoad = true
        isBusy = true
        notice = nil

        defer { isBusy = false }
        do {
            try access.connect()
            guard let dictionary = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidPlist
            }
            plist = GestaltPlist(dict: dictionary)
            baselineDictionary = dictionary
            DeviceIdentityStore.captureIfNeeded(from: dictionary["CacheExtra"] as? [String: Any] ?? [:])
            isDirty = false
            refreshBackups()
        } catch {
            plist = nil
            report(error)
        }
    }

    /// Values the identity panel shows, plus whether the file currently carries
    /// a spoofed identity written by the force-AI path or anything similar.
    var deviceIdentity: DeviceIdentityView {
        let values = plist?.cacheExtra ?? [:]
        let real = values["0+nc/Udy4WNG8S+Q7a/s1A"] as? String
        let mg = values["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String
        let hasFlags = values["A62OafQ85EJAiiqKn4agtg"] != nil
            || values["a3n5T9sFtlyQ74NEp9ESxg"] != nil
        return DeviceIdentityView(
            realProductType: real,
            mgProductType: mg,
            hardwareModel: values["oYicEKzVTz4/CxxE05pEgQ"] as? String,
            cpuModel: values["5pYKlGnYYBzGvAlIU8RjEQ"] as? String,
            regulatoryModel: values["97JDvERpVwO+GHtthIh7hA"] as? String,
            hasSpoofFlags: hasFlags,
            snapshotDate: DeviceIdentityStore.snapshot()?.capturedAt
        )
    }

    var isIdentitySpoofed: Bool {
        let identity = deviceIdentity
        if identity.hasSpoofFlags { return true }
        guard let real = identity.realProductType, let mg = identity.mgProductType else {
            return false
        }
        return real != mg
    }

    var canRestoreIdentity: Bool {
        DeviceIdentityStore.snapshot() != nil
    }

    /// Puts only the identity keys back to the recorded real values. Keys that
    /// were absent originally are removed so the system default applies.
    func restoreIdentity() {
        guard !isBusy, var pending = plist, let snapshot = DeviceIdentityStore.snapshot() else {
            return
        }
        for key in DeviceIdentityStore.keys {
            if let original = snapshot.values[key] {
                pending.setCacheExtra(original, forKey: key)
            } else {
                pending.removeCacheExtraValue(forKey: key)
            }
        }
        requestWrite(
            pending,
            source: .tweaks,
            riskyItems: [String(localized: "Restore official device identity")]
        )
    }

    /// Stages the toggle position; `nil` would mean "same as the file", so a flip
    /// back to the real state simply drops the override.
    func setTweakDesired(_ id: GestaltTweakID, enabled: Bool) {
        if enabled == isApplied(id) {
            tweakOverrides.removeValue(forKey: id)
        } else {
            tweakOverrides[id] = enabled
        }

        // These two write the same key with opposite values, so keep them exclusive.
        if id == .enableLiquidGlassLowPerformance, enabled {
            if isApplied(.disableLiquidGlassLowPerformance) {
                tweakOverrides[.disableLiquidGlassLowPerformance] = false
            }
        } else if id == .disableLiquidGlassLowPerformance, enabled {
            if isApplied(.enableLiquidGlassLowPerformance) {
                tweakOverrides[.enableLiquidGlassLowPerformance] = false
            }
        }
    }

    func setAIRegion(enabled: Bool) {
        stagesAIRegion = enabled
        if enabled, requiresForcedAIEnable {
            notice = GestaltNotice(
                kind: .riskWarning,
                message: String(localized: "This device does not officially support Siri AI. Force enabling spoofs the product, hardware, and CPU model. It may temporarily break Face ID, cause system instability or boot loops, and could require restoring the device. A backup will be created before writing.")
            )
        }
    }

    func applySelectedTweaks() {
        guard !isBusy, var pending = plist else { return }
        do {
            let startingPlist = plist
            var newOriginals: [GestaltTweakID: [String: Any]] = [:]
            var revertedIDs: [GestaltTweakID] = []

            for definition in GestaltTweakCatalog.definitions {
                guard let desired = tweakOverrides[definition.id] else { continue }
                let applied = startingPlist?.matches(definition: definition) ?? false
                if desired, !applied {
                    if TweakStateStore.rememberedValues(for: definition.id) == nil,
                       let originals = startingPlist?.originalValues(for: definition) {
                        newOriginals[definition.id] = originals
                    }
                    try pending.apply(definition: definition)
                } else if !desired, applied {
                    let originals = TweakStateStore.rememberedValues(for: definition.id) ?? [:]
                    pending.revert(definition: definition, originals: originals)
                    revertedIDs.append(definition.id)
                }
            }
            if let dynamicIslandSubtype {
                try pending.setDynamicIslandSubtype(dynamicIslandSubtype)
            }
            if changesModelName {
                let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw GestaltEditError.emptyModelName }
                try pending.setModelName(name)
            }
            var expectedConfiguration: AIRegionConfiguration?
            if stagesAIRegion {
                let configuration = AIRegionConfiguration.resolve(for: pending)
                let profile = configuration.profile
                if let productType = configuration.spoofedProductType,
                   let hardwareModel = configuration.spoofedHardwareModel,
                   let cpuModel = configuration.spoofedCPUModel {
                    pending.setCacheExtra(1, forKey: "A62OafQ85EJAiiqKn4agtg")
                    pending.setCacheExtra(2, forKey: "a3n5T9sFtlyQ74NEp9ESxg")
                    pending.setCacheExtra(productType, forKey: "h9jDsbgj7xIVeIQ8S3/X3Q")
                    pending.setCacheExtra(hardwareModel, forKey: "oYicEKzVTz4/CxxE05pEgQ")
                    pending.setCacheExtra(cpuModel, forKey: "5pYKlGnYYBzGvAlIU8RjEQ")
                }
                pending.setCacheExtra("LL", forKey: "h63QSdBCiT/z0WU6rdQv6Q")
                pending.setCacheExtra("LL/A", forKey: "yK+xavymRGZ3xWc1tb8XDg")
                pending.setCacheExtra(profile.regulatoryModel, forKey: "97JDvERpVwO+GHtthIh7hA")
                expectedConfiguration = configuration
            }
            let stagedIPadModeForWrite = stagedIPadMode
            let priorRecord = IPadModeStore.load()
            var ipadRecord: IPadModeRecord?
            if let staged = stagedIPadMode {
                switch staged {
                case .full:
                    var previousValues = priorRecord?.previousValues ?? [:]
                    for key in GestaltPlist.keys(for: .full) where previousValues[key] == nil {
                        if let value = pending.cacheExtra[key] as? Int { previousValues[key] = value }
                    }
                    let newPatch = try pending.enableIPadMode()
                    // Keep the very first recorded nibble, so repeated applies still
                    // revert to the original phone state rather than to "already iPad".
                    let keptPatch = priorRecord?.patch.flatMap { old -> IPadDeviceClassPatch? in
                        old.nibbleOffset == newPatch.nibbleOffset ? old : nil
                    }
                    ipadRecord = IPadModeRecord(
                        mode: .full,
                        patch: keptPatch ?? newPatch,
                        previousValues: previousValues,
                        writtenKeys: Set(GestaltPlist.keys(for: .full))
                            .union(priorRecord?.writtenKeys ?? [])
                            .sorted()
                    )
                case .capabilities:
                    // A device class written outside this app cannot be undone here.
                    if priorRecord == nil, pending.appliedIPadMode == .full {
                        throw GestaltTweakError.ipadModeNotRevertible
                    }
                    // Leave the iPad device class behind when coming from full mode.
                    if let priorRecord {
                        try pending.restoreIPadMode(using: priorRecord)
                    }
                    var previousValues: [String: Int] = [:]
                    for key in GestaltPlist.keys(for: .capabilities) {
                        if let value = pending.cacheExtra[key] as? Int { previousValues[key] = value }
                    }
                    pending.enableIPadCapabilities()
                    ipadRecord = IPadModeRecord(
                        mode: .capabilities,
                        patch: nil,
                        previousValues: previousValues,
                        writtenKeys: GestaltPlist.keys(for: .capabilities)
                    )
                case .off:
                    guard let priorRecord else {
                        throw GestaltTweakError.ipadModeNotRevertible
                    }
                    try pending.restoreIPadMode(using: priorRecord)
                    ipadRecord = nil
                }
            }

            let expectedPatch = ipadRecord?.patch
            let ipadValidation: ((GestaltPlist) throws -> Void)?
            if let staged = stagedIPadMode {
                ipadValidation = { verifiedPlist in
                    switch staged {
                    case .full:
                        guard verifiedPlist.appliedIPadMode == .full else {
                            throw GestaltEditError.verificationFailed
                        }
                        if let expectedPatch,
                           !verifiedPlist.deviceClassMatches(expectedPatch) {
                            throw GestaltEditError.verificationFailed
                        }
                    case .capabilities:
                        guard verifiedPlist.appliedIPadMode == .capabilities else {
                            throw GestaltEditError.verificationFailed
                        }
                    case .off:
                        guard verifiedPlist.appliedIPadMode == nil else {
                            throw GestaltEditError.verificationFailed
                        }
                    }
                }
            } else {
                ipadValidation = nil
            }

            var riskyItems: [String] = []
            for definition in GestaltTweakCatalog.definitions where definition.isRisky {
                if tweakOverrides[definition.id] == true {
                    riskyItems.append(definition.title)
                }
            }
            if stagedIPadMode == .full {
                riskyItems.append(String(localized: "Full iPadOS mode"))
            }
            if stagesAIRegion, requiresForcedAIEnable {
                riskyItems.append(String(localized: "Forced Siri AI spoofing"))
            }

            requestWrite(
                pending,
                expectedAIRegion: expectedConfiguration,
                source: .tweaks,
                validation: ipadValidation,
                riskyItems: riskyItems
            ) { [weak self] in
                if stagedIPadModeForWrite != nil {
                    IPadModeStore.save(ipadRecord)
                }
                for (id, values) in newOriginals {
                    TweakStateStore.remember(values, for: id)
                }
                for id in revertedIDs {
                    TweakStateStore.forget(id)
                }
                self?.tweakOverrides.removeAll()
                self?.dynamicIslandSubtype = nil
                self?.changesModelName = false
                self?.modelName = ""
                self?.stagesAIRegion = false
                self?.stagedIPadMode = nil
            }
        } catch {
            report(error)
        }
    }

    func applyChanges() {
        guard !isBusy, let plist else { return }
        requestWrite(plist, source: .fieldEditor)
    }

    // MARK: - Previewed writes

    private func requestWrite(
        _ pendingPlist: GestaltPlist,
        expectedAIRegion: AIRegionConfiguration? = nil,
        source: BackupChangeSource,
        validation: ((GestaltPlist) throws -> Void)? = nil,
        riskyItems: [String] = [],
        completion: (() -> Void)? = nil
    ) {
        let changeSet = GestaltChangeDiff.changes(
            old: baselineDictionary,
            new: pendingPlist.dict,
            source: source
        )
        guard changeSet.total > 0 || !riskyItems.isEmpty else {
            notice = GestaltNotice(
                kind: .info,
                message: String(localized: "Nothing would change, so nothing was written.")
            )
            return
        }
        pendingWrite = PendingWrite(
            plist: pendingPlist,
            expectedAIRegion: expectedAIRegion,
            source: source,
            validation: validation,
            completion: completion
        )
        writePreview = WritePreview(
            source: source,
            changeSet: changeSet,
            riskyItems: riskyItems
        )
    }

    func confirmWrite() {
        guard let pending = pendingWrite else { return }
        pendingWrite = nil
        writePreview = nil
        save(
            pending.plist,
            expectedAIRegion: pending.expectedAIRegion,
            source: pending.source,
            validation: pending.validation,
            completion: pending.completion
        )
    }

    func cancelWrite() {
        pendingWrite = nil
        writePreview = nil
    }

    // MARK: - Respring lifecycle

    func beginRespring() {
        isRespringing = true
        respringTimeout?.cancel()
        respringTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.endRespring()
        }
    }

    func endRespring() {
        respringTimeout?.cancel()
        respringTimeout = nil
        if isRespringing {
            isRespringing = false
        }
    }

    func manualRespring() {
        guard !isBusy else { return }
        beginRespring()
    }

    // MARK: - Undo

    var lastAutoBackup: GestaltBackup? {
        guard let name = lastAutoBackupName else { return nil }
        return backups.first { $0.name == name }
    }

    func undoLastWrite() {
        guard !isBusy, let backup = lastAutoBackup else { return }
        restore(backup, clearingUndoMarker: true)
    }

    private func rememberAutoBackup(_ backup: GestaltBackup) {
        lastAutoBackupName = backup.name
        UserDefaults.standard.set(backup.name, forKey: Self.lastAutoBackupKey)
    }

    private func clearUndoMarker() {
        lastAutoBackupName = nil
        UserDefaults.standard.removeObject(forKey: Self.lastAutoBackupKey)
    }

    func createBackup() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try access.connect()
            let data = try access.readGestaltData()
            let backup = try GestaltBackupStore.create(from: data, manual: true)
            refreshBackups()
            notice = GestaltNotice(
                kind: .backupCreated,
                message: String(
                    format: String(localized: "Saved %@.plist. You can export it from the Backups tab."),
                    backup.name
                )
            )
        } catch {
            report(error)
        }
    }

    func importBackup(from url: URL) {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let dictionary = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any],
                  dictionary["CacheExtra"] is [String: Any] else {
                throw GestaltEditError.invalidBackup
            }
            let backup = try GestaltBackupStore.create(from: data, manual: true)
            refreshBackups()
            notice = GestaltNotice(
                kind: .backupCreated,
                message: String(
                    format: String(localized: "Imported %@ and saved it as %@.plist."),
                    url.lastPathComponent,
                    backup.name
                )
            )
        } catch {
            report(error)
        }
    }

    func restore(_ backup: GestaltBackup) {
        restore(backup, clearingUndoMarker: false)
    }

    private func restore(_ backup: GestaltBackup, clearingUndoMarker: Bool) {
        guard !isBusy else { return }
        do {
            let data = try GestaltBackupStore.data(for: backup)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let dictionary = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any],
                  dictionary["CacheExtra"] is [String: Any] else {
                throw GestaltEditError.invalidBackup
            }
            save(
                GestaltPlist(dict: dictionary),
                expectedAIRegion: nil,
                source: .restore,
                completion: { [weak self] in
                    self?.clearStagedState()
                    if clearingUndoMarker { self?.clearUndoMarker() }
                }
            )
        } catch {
            report(error)
        }
    }

    private func clearStagedState() {
        tweakOverrides.removeAll()
        dynamicIslandSubtype = nil
        changesModelName = false
        modelName = ""
        stagesAIRegion = false
        stagedIPadMode = nil
    }

    /// Restores a single field from a backup, leaving every other key untouched.
    func restoreChange(_ change: BackupChange, from backup: GestaltBackup) {
        guard !isBusy, let current = plist else { return }
        do {
            let data = try GestaltBackupStore.data(for: backup)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let dictionary = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any] else {
                throw GestaltEditError.invalidBackup
            }

            let cacheExtraPrefix = "CacheExtra/"
            let isCacheExtra = change.key.hasPrefix(cacheExtraPrefix)
            let key = isCacheExtra ? String(change.key.dropFirst(cacheExtraPrefix.count)) : change.key
            let sourceValues = isCacheExtra
                ? (dictionary["CacheExtra"] as? [String: Any] ?? [:])
                : dictionary

            var pending = current
            if let value = sourceValues[key] {
                if isCacheExtra {
                    pending.setCacheExtra(value, forKey: key)
                } else {
                    pending.setValue(value, forKey: key)
                }
            } else if isCacheExtra {
                pending.removeCacheExtraValue(forKey: key)
            } else {
                pending.dict.removeValue(forKey: key)
            }
            requestWrite(pending, source: .restore)
        } catch {
            report(error)
        }
    }

    /// Human-readable snapshot of everything the app can observe right now.
    var diagnosticsReport: String {
        var lines: [String] = []
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let groupID = "group." + (bundle.bundleIdentifier ?? "me.ssus.gestaltedit")

        lines.append("GestaltEdit \(version) (\(build))")
        lines.append("iOS: \(os)")
        lines.append(String(format: String(localized: "App Group: %@"), groupID))

        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) {
            lines.append(String(format: String(localized: "App Group container: %@"), container.path))
        } else {
            lines.append(String(localized: "App Group container unavailable (entitlement missing?)"))
        }

        if let plist {
            lines.append(String(format: String(localized: "Read: OK, %lld CacheExtra keys"), plist.cacheExtraKeys.count))
            let cacheData = plist.dict["CacheData"] as? Data
            lines.append(String(format: String(localized: "CacheData: %@"), cacheData.map { "\($0.count) bytes" } ?? "missing"))
        } else {
            lines.append(String(localized: "Read: failed; the file could not be parsed"))
        }

        if let offset = DeviceClassLocator.cacheDataOffset() {
            let value = plist?.deviceClassValue(at: offset)
            lines.append(
                String(
                    format: String(localized: "Device class: offset %lld, value %@"),
                    offset,
                    value.map { String($0) } ?? "?"
                )
            )
        } else {
            lines.append(String(localized: "Device class: libMobileGestalt metadata unavailable"))
        }

        lines.append(
            String(
                format: String(localized: "iPadOS record: %@"),
                IPadModeStore.load().map { String(describing: $0.mode) } ?? "none"
            )
        )
        lines.append(String(format: String(localized: "Tweaks applied: %lld"), appliedTweakCount))
        lines.append(String(format: String(localized: "Backups: %lld"), backups.count))

        if let notice {
            lines.append(String(format: String(localized: "Last message: %@"), notice.message))
        }
        return lines.joined(separator: "\n")
    }

    func delete(_ backup: GestaltBackup) {
        delete([backup])
    }

    func delete(_ backups: [GestaltBackup]) {
        guard !backups.isEmpty else { return }
        var failure: Error?
        for backup in backups {
            do {
                try GestaltBackupStore.delete(backup)
            } catch {
                failure = failure ?? error
            }
        }
        refreshBackups()
        if let failure {
            report(failure)
        }
    }

    func refreshBackups() {
        do {
            backups = try GestaltBackupStore.list()
        } catch {
            report(error)
        }
    }

    private func save(
        _ pendingPlist: GestaltPlist,
        expectedAIRegion: AIRegionConfiguration?,
        source: BackupChangeSource = .tweaks,
        validation: ((GestaltPlist) throws -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        isBusy = true
        notice = nil
        var wrote = false
        var originalDictionary: [String: Any] = [:]

        do {
            let originalData = try access.readGestaltData()
            var format = PropertyListSerialization.PropertyListFormat.binary
            originalDictionary = (try? PropertyListSerialization.propertyList(
                from: originalData,
                options: [],
                format: &format
            )) as? [String: Any] ?? [:]
            let changeSet = GestaltChangeDiff.changes(
                old: originalDictionary,
                new: pendingPlist.dict,
                source: source
            )
            let originalBackup = try GestaltBackupStore.create(from: originalData)
            try access.saveGestalt(pendingPlist.dict)
            wrote = true
            guard let verification = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidPlist
            }
            let verifiedPlist = GestaltPlist(dict: verification)

            if let expectedAIRegion {
                let cacheExtra = verifiedPlist.cacheExtra
                guard cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "LL",
                      cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] as? String == "LL/A",
                      cacheExtra["97JDvERpVwO+GHtthIh7hA"] as? String == expectedAIRegion.profile.regulatoryModel else {
                    throw GestaltEditError.verificationFailed
                }
                if expectedAIRegion.requiresDeviceSpoofing {
                    guard cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int == 1,
                          cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] as? Int == 2,
                          cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String == expectedAIRegion.spoofedProductType,
                          cacheExtra["oYicEKzVTz4/CxxE05pEgQ"] as? String == expectedAIRegion.spoofedHardwareModel,
                          cacheExtra["5pYKlGnYYBzGvAlIU8RjEQ"] as? String == expectedAIRegion.spoofedCPUModel else {
                        throw GestaltEditError.verificationFailed
                    }
                }
            }

            try validation?(verifiedPlist)

            if changeSet.total > 0 {
                try? GestaltBackupStore.attach(changeSet, to: originalBackup)
            }

            plist = verifiedPlist
            baselineDictionary = verification
            isDirty = false
            rememberAutoBackup(originalBackup)
            completion?()
            refreshBackups()
            isBusy = false
            beginRespring()
        } catch {
            isDirty = true
            isBusy = false
            if wrote, !originalDictionary.isEmpty {
                let rolledBack = rollback(to: originalDictionary)
                if rolledBack { isDirty = false }
                let suffix = rolledBack
                    ? String(localized: "The write did not verify, so the previous file was restored automatically.")
                    : String(localized: "The write did not verify and the automatic rollback failed. Restore the newest backup from the Restore tab.")
                notice = GestaltNotice(
                    kind: .error,
                    message: error.localizedDescription + "\n\n" + suffix
                )
            } else {
                report(error)
            }
        }
    }

    /// Puts the file back using the in-memory copy taken before the write.
    private func rollback(to dictionary: [String: Any]) -> Bool {
        do {
            try access.saveGestalt(dictionary)
            if let verification = try access.readGestalt() as? [String: Any] {
                plist = GestaltPlist(dict: verification)
                baselineDictionary = verification
            }
            return true
        } catch {
            return false
        }
    }

    private func report(_ error: Error) {
        notice = GestaltNotice(kind: .error, message: error.localizedDescription)
    }
}

private enum GestaltEditError: LocalizedError {
    case invalidPlist
    case invalidBackup
    case verificationFailed
    case emptyModelName

    var errorDescription: String? {
        switch self {
        case .invalidPlist: String(localized: "The MobileGestalt plist is not a valid dictionary.")
        case .invalidBackup: String(localized: "The backup is not a valid MobileGestalt plist.")
        case .verificationFailed: String(localized: "The MobileGestalt values after writing do not match the expected values.")
        case .emptyModelName: String(localized: "The device model name cannot be empty.")
        }
    }
}
