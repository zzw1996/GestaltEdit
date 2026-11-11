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
    let recordedPatch: IPadDeviceClassPatch?
}

@MainActor
final class GestaltViewModel: ObservableObject {
    @Published var plist: GestaltPlist?
    @Published var isDirty = false
    @Published var isBusy = false
    @Published var notice: GestaltNotice?
    @Published private(set) var hasAttemptedLoad = false
    @Published private(set) var backups: [GestaltBackup] = []
    @Published var selectedTweaks: Set<GestaltTweakID> = []
    @Published var dynamicIslandSubtype: Int?
    @Published var changesModelName = false
    @Published var modelName = ""
    @Published var stagesAIRegion = false
    @Published var stagedIPadMode: IPadModeChoice?
    @Published private(set) var isRespringing = false

    private let access = GestaltAccess.shared()

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
        !selectedTweaks.isEmpty
            || dynamicIslandSubtype != nil
            || (changesModelName && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || stagesAIRegion
            || stagedIPadMode != nil
    }

    var stagedChangeCount: Int {
        selectedTweaks.count
            + (dynamicIslandSubtype == nil ? 0 : 1)
            + (changesModelName ? 1 : 0)
            + (stagesAIRegion ? 1 : 0)
            + (stagedIPadMode == nil ? 0 : 1)
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
        return IPadStatusSnapshot(
            mode: currentIPadMode,
            hasIdentity: identity,
            stageManagerEnabled: stageManager,
            capabilityCount: capabilityCount,
            deviceClassNibble: nibble,
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
            isDirty = false
            refreshBackups()
        } catch {
            plist = nil
            report(error)
        }
    }

    func setTweak(_ id: GestaltTweakID, enabled: Bool) {
        if enabled {
            selectedTweaks.insert(id)
            if id == .enableLiquidGlassLowPerformance {
                selectedTweaks.remove(.disableLiquidGlassLowPerformance)
            } else if id == .disableLiquidGlassLowPerformance {
                selectedTweaks.remove(.enableLiquidGlassLowPerformance)
            }
        } else {
            selectedTweaks.remove(id)
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
            for id in selectedTweaks {
                guard let definition = GestaltTweakCatalog.definition(for: id) else { continue }
                try pending.apply(definition: definition)
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

            let expectedNibbleOffset = ipadRecord?.patch?.nibbleOffset
            let ipadValidation: ((GestaltPlist) throws -> Void)?
            if let staged = stagedIPadMode {
                ipadValidation = { verifiedPlist in
                    switch staged {
                    case .full:
                        guard verifiedPlist.appliedIPadMode == .full else {
                            throw GestaltEditError.verificationFailed
                        }
                        if let expectedNibbleOffset,
                           verifiedPlist.deviceClassNibble(at: expectedNibbleOffset) != "3" {
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

            save(pending, expectedAIRegion: expectedConfiguration, source: .tweaks, validation: ipadValidation) { [weak self] in
                if stagedIPadModeForWrite != nil {
                    IPadModeStore.save(ipadRecord)
                }
                self?.selectedTweaks.removeAll()
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
        save(plist, expectedAIRegion: nil, source: .fieldEditor)
    }

    func createBackup() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try access.connect()
            let data = try access.readGestaltData()
            let backup = try GestaltBackupStore.create(from: data)
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
            let backup = try GestaltBackupStore.create(from: data)
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
        guard !isBusy else { return }
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
            save(GestaltPlist(dict: dictionary), expectedAIRegion: nil, source: .restore)
        } catch {
            report(error)
        }
    }

    func delete(_ backup: GestaltBackup) {
        do {
            try GestaltBackupStore.delete(backup)
            refreshBackups()
        } catch {
            report(error)
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

        do {
            let originalData = try access.readGestaltData()
            var format = PropertyListSerialization.PropertyListFormat.binary
            let originalDictionary = (try? PropertyListSerialization.propertyList(
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
            isDirty = false
            completion?()
            refreshBackups()
            isBusy = false
            isRespringing = true
        } catch {
            isDirty = true
            report(error)
            isBusy = false
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
