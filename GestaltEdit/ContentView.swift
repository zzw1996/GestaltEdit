import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
                TabView {
                    TweakWorkbench()
                        .tabItem { Label("Tools", systemImage: "switch.2") }

                    NavigationStack { AdvancedGestaltEditor() }
                        .tabItem { Label("Fields", systemImage: "list.bullet.rectangle") }

                    BackupLibrary()
                        .tabItem { Label("Restore", systemImage: "archivebox") }
                }
                .task { viewModel.load() }
        }
        .overlay {
            if viewModel.isRespringing {
                ZStack(alignment: .bottom) {
                    NeoSpringView()

                    Button {
                        viewModel.endRespring()
                    } label: {
                        Text("Respring is not responding? Tap here")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                    .padding(.bottom, 40)
                    .accessibilityHint("Closes the overlay and returns to the app.")
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.endRespring()
            }
        }
        .sheet(item: $viewModel.writePreview) { preview in
            WritePreviewSheet(
                preview: preview,
                onCancel: { viewModel.cancelWrite() },
                onConfirm: { viewModel.confirmWrite() }
            )
        }
        .alert(item: $viewModel.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct TweakWorkbench: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @State private var showsPresetPrompt = false
    @State private var presetName = ""
    @State private var showsExperimental = false
    @State private var showsSpoofPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section { deviceStatus }

                if let backup = viewModel.lastAutoBackup {
                    Section {
                        Button {
                            viewModel.undoLastWrite()
                        } label: {
                            Label("Undo Last Write", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(viewModel.isBusy)

                        Text(backup.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Safety")
                    } footer: {
                        Text("Restores the snapshot taken right before the last write, then resprings.")
                    }
                }

                if viewModel.plist != nil {
                    regionStatusSection
                    deviceIdentitySection
                    tweakSection(.region)
                    dynamicIslandSection
                    modelNameSection
                    ipadModeSection
                    ipadStatusSection
                    ipadUsageSection

                    Section {
                        if viewModel.pendingTweakChangeCount > 0 {
                            LabeledContent(
                                "Pending switches",
                                value: "\(viewModel.pendingTweakChangeCount)"
                            )
                        }
                        LabeledContent(
                            "Applied tweaks",
                            value: "\(viewModel.appliedTweakCount) / \(GestaltTweakCatalog.definitions.count)"
                        )
                    } footer: {
                        Text("Switches show what the file on disk really holds. Turning one off writes the values recorded when GestaltEdit first enabled it, or removes the keys so the system default applies.")
                    }

                    presetsSection

                    ForEach(GestaltTweakCategory.allCases.filter { $0 != .region && $0 != .experimental }) { category in
                        tweakSection(category)
                    }

                    experimentalSection

                }

                Section(String(localized: "Developer")) {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }

                    DeveloperFooter()

                    PlacardPromotionLink()

                    NavigationLink {
                        RewardCodeView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                                .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("打赏开发者")
                                Text("扫描赞赏码支持 SUSS")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .frame(minHeight: 40)
                    }
                }
            }
            .navigationTitle("MobileGestalt")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.manualRespring()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .accessibilityLabel("Respring")
                    .disabled(viewModel.isBusy)
                }
            }
            .refreshable { viewModel.load() }
            .safeAreaInset(edge: .bottom) {
                if viewModel.hasStagedTweaks {
                    applyBar
                }
            }
            .alert("Save Preset", isPresented: $showsPresetPrompt) {
                TextField("Preset name", text: $presetName)
                Button("Cancel", role: .cancel) { presetName = "" }
                Button("Save") {
                    if viewModel.saveCurrentAsPreset(name: presetName) {
                        presetName = ""
                    }
                }
            } message: {
                Text("Saves the tweaks the file currently has applied, so they can be staged again later.")
            }
        }
    }

    @ViewBuilder
    private var regionStatusSection: some View {
        let snapshot = viewModel.regionSnapshot
        Section {
            LabeledContent("Device", value: snapshot.device)
            LabeledContent("Region code", value: snapshot.code)
            LabeledContent("Region info", value: snapshot.info)
            LabeledContent("Regulatory model", value: snapshot.regulatory)
        } header: {
            Text("Region & Device")
        } footer: {
            Text("Read-only values from MobileGestalt, shown so you can check what the file really contains.")
        }
    }

    private var presetsSection: some View {
        Section {
            Button {
                showsPresetPrompt = true
            } label: {
                Label("Save Current as Preset", systemImage: "plus.square.on.square")
            }

            if !viewModel.customPresets.isEmpty {
                ShareLink(
                    item: viewModel.presetExportJSON,
                    preview: SharePreview("GestaltEdit presets")
                ) {
                    Label("Export Presets (JSON)", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                viewModel.importPresets(fromJSON: UIPasteboard.general.string ?? "")
            } label: {
                Label("Import Presets from Clipboard", systemImage: "doc.on.clipboard")
            }

            if viewModel.customPresets.isEmpty {
                Text("No saved presets")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.customPresets) { preset in
                    Button {
                        viewModel.applyPreset(preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .foregroundStyle(.primary)
                                Text(String(format: String(localized: "%lld tweaks"), preset.tweakIDs.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .onDelete { offsets in
                    let selected = offsets.compactMap { index in
                        viewModel.customPresets.indices.contains(index)
                            ? viewModel.customPresets[index]
                            : nil
                    }
                    for preset in selected {
                        viewModel.deletePreset(preset)
                    }
                }
            }
        } header: {
            Text("Custom Presets")
        } footer: {
            Text("Applying a preset only stages the tweaks it contains; review the change preview before writing.")
        }
    }

    private func tweakSection(_ category: GestaltTweakCategory) -> some View {
        let definitions = GestaltTweakCatalog.definitions.filter { $0.category == category }
        return Section(category.label) {
            ForEach(definitions) { definition in
                tweakRow(definition)
            }
            if category == .region {
                Toggle(
                    isOn: Binding(
                        get: { viewModel.stagesAIRegion },
                        set: { viewModel.setAIRegion(enabled: $0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Enable Siri AI (US Region)")
                            if viewModel.requiresForcedAIEnable {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("High Risk")
                            }
                        }
                        if viewModel.requiresForcedAIEnable {
                            Text("Unsupported device: force enable with device identity spoofing. Face ID or system stability may be affected.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func tweakRow(_ definition: GestaltTweakDefinition) -> some View {
        TweakToggle(
            definition: definition,
            isOn: Binding(
                get: { viewModel.desiredState(for: definition.id) },
                set: { viewModel.setTweakDesired(definition.id, enabled: $0) }
            ),
            isApplied: viewModel.isApplied(definition.id),
            isPending: viewModel.tweakOverrides[definition.id].map {
                $0 != viewModel.isApplied(definition.id)
            } ?? false
        )
    }

    private var experimentalSection: some View {
        let definitions = GestaltTweakCatalog.definitions.filter { $0.category == .experimental }
        return Section {
            DisclosureGroup(isExpanded: $showsExperimental) {
                ForEach(definitions) { definition in
                    tweakRow(definition)
                }
            } label: {
                Label("Experimental (unverified)", systemImage: "flask")
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Keys reported by other MobileGestalt tools but not verified on this device. A wrong value can break system features, so every switch here is treated as high risk and requires confirmation.")
        }
    }

    @ViewBuilder
    private var deviceIdentitySection: some View {
        let identity = viewModel.deviceIdentity
        Section {
            identityRow("Real product type", identity.realProductType)
            identityRow("MG product type", identity.mgProductType)
            identityRow("Hardware model", identity.hardwareModel)
            identityRow("CPU model", identity.cpuModel)

            Button {
                showsSpoofPicker = true
            } label: {
                Label("Spoof Device Model", systemImage: "theatermasks")
            }
            .disabled(viewModel.isBusy)

            if viewModel.isIdentitySpoofed {
                Label("Identity is spoofed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Button {
                    viewModel.restoreIdentity()
                } label: {
                    Label("Restore Official Identity", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(!viewModel.canRestoreIdentity || viewModel.isBusy)
            }
        } header: {
            Text("Device Identity")
        } footer: {
            if let date = identity.snapshotDate {
                Text(String(
                    format: String(localized: "Real identity snapshot recorded %@."),
                    date.formatted(date: .abbreviated, time: .shortened)
                ))
            } else {
                Text("No identity snapshot yet; restore is unavailable until the app has read the file once.")
            }
        }
        .sheet(isPresented: $showsSpoofPicker) {
            DeviceSpoofView()
                .environmentObject(viewModel)
        }
    }

    @ViewBuilder
    private func identityRow(_ title: LocalizedStringKey, _ value: String?) -> some View {        LabeledContent {
            Text(value ?? "—")
                .font(.caption.monospaced())
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }

    @ViewBuilder
    private var deviceStatus: some View {
        if viewModel.plist == nil {
            HStack(spacing: 10) {
                if viewModel.isBusy || !viewModel.hasAttemptedLoad {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading MobileGestalt…")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unable to read MobileGestalt")
                        HStack(spacing: 12) {
                            Button("Reload", action: viewModel.load)
                                .font(.footnote)
                            NavigationLink("Diagnostics") { DiagnosticsView() }
                                .font(.footnote)
                        }
                    }
                }
            }
        } else {
            LabeledContent {
                Text("Connected")
                    .foregroundStyle(.green)
            } label: {
                Label(viewModel.aiRegionProfile?.marketingName ?? String(localized: "Current Device"), systemImage: "iphone")
            }
        }
    }

    private var dynamicIslandSection: some View {
        Section {
            Picker("Device Subtype", selection: $viewModel.dynamicIslandSubtype) {
                Text("No Change").tag(Int?.none)
                ForEach(DynamicIslandOption.all) { option in
                    Text("\(option.subtype) · \(option.title)").tag(Int?.some(option.subtype))
                }
            }
        } header: {
            Text("Dynamic Island")
        } footer: {
            Text("Selecting a subtype writes ArtworkDeviceSubType and the Dynamic Island support flag.")
        }
    }

    private var modelNameSection: some View {
        Section("Device Name") {
            Toggle("Change model name in About", isOn: $viewModel.changesModelName)
            if viewModel.changesModelName {
                TextField("Model Name", text: $viewModel.modelName)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    private var ipadModeSection: some View {
        Section {
            Picker(
                "iPadOS Mode",
                selection: Binding(
                    get: {
                        viewModel.stagedIPadMode
                            ?? (viewModel.currentIPadMode == .full ? .full : .off)
                    },
                    set: { viewModel.setIPadMode($0) }
                )
            ) {
                Text("Off").tag(IPadModeChoice.off)
                Text("Full iPadOS").tag(IPadModeChoice.full)
            }
            .pickerStyle(.inline)
            .disabled(viewModel.isBusy)
        } header: {
            Text("iPadOS Mode")
        } footer: {
            Text(ipadModeFooter)
        }
    }

    private var ipadModeFooter: String {
        if viewModel.stagedIPadMode == nil, viewModel.currentIPadMode == .capabilities {
            return String(localized: "Capability flags left by an earlier version do not bring up the window UI. Choose Off to clear them.")
        }
        switch viewModel.stagedIPadMode ?? viewModel.currentIPadMode {
        case .off:
            return String(localized: "iPhone device class without iPad multitasking flags. Apps keep phone layouts.")
        case .capabilities:
            return String(localized: "Capability flags alone were verified not to bring up the window UI.")
        case .full:
            return String(localized: "Switches the device class to iPad. iPadOS window features require this; iPhone-only apps keep their phone layouts, but apps that support iPad adopt tablet layouts.")
        }
    }

    private var ipadStatusSection: some View {
        Section {
            LabeledContent("Device class", value: deviceClassDescription)
            LabeledContent("iPad identity flag", value: viewModel.ipadStatus.hasIdentity
                ? String(localized: "Enabled")
                : String(localized: "Disabled"))
            LabeledContent("Multitasking flags", value: "\(viewModel.ipadStatus.capabilityCount)/4")
            LabeledContent("Stage Manager flag", value: viewModel.ipadStatus.stageManagerEnabled
                ? String(localized: "Enabled")
                : String(localized: "Disabled"))
            if let offset = viewModel.ipadStatus.resolvedOffset {
                LabeledContent("Device class offset", value: "0x\(String(offset, radix: 16)) (\(offset))")
            }
            Button {
                UIPasteboard.general.string = diagnosticText
            } label: {
                Label("Copy Diagnostics", systemImage: "doc.on.doc")
            }
        } header: {
            Text("iPadOS Status")
        } footer: {
            Text("Values are read back from the plist on disk, so they reflect what the system will use after the next respring.")
        }
    }

    private var deviceClassDescription: String {
        if let value = viewModel.ipadStatus.deviceClassValue {
            switch value {
            case 3: return String(localized: "iPad (3)")
            case 1: return String(localized: "iPhone (1)")
            default: return String(localized: "Unknown value")
            }
        }
        switch viewModel.ipadStatus.deviceClassNibble {
        case "3": return String(localized: "iPad (3)")
        case "1": return String(localized: "iPhone (1)")
        default: return String(localized: "Unknown (not written by GestaltEdit)")
        }
    }

    private var diagnosticText: String {
        let status = viewModel.ipadStatus
        var lines = [
            "GestaltEdit iPadOS diagnostics",
            "mode=\(status.mode)",
            "deviceClassValue=\(status.deviceClassValue.map { String($0) } ?? "unknown")",
            "deviceClassNibble=\(status.deviceClassNibble ?? "unknown")",
            "offset=\(status.resolvedOffset.map { "0x\(String($0, radix: 16))" } ?? "unresolved")",
            "identity=\(status.hasIdentity)",
            "multitaskingFlags=\(status.capabilityCount)/4",
            "stageManager=\(status.stageManagerEnabled)"
        ]
        if let patch = status.recordedPatch {
            lines.append("nibbleOffset=\(patch.nibbleOffset) original=\(patch.originalNibble)")
        }
        return lines.joined(separator: "\n")
    }

    private var ipadUsageSection: some View {
        Section {
            DisclosureGroup("How to Use Windows and Split View") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Settings → Multitasking & Gestures → Windowed Apps.")
                    Text("2. Turn off Rotation Lock in Control Center before testing orientation.")
                    Text("3. iPadOS only tiles side by side: drag a window to the left or right edge. There is no top/bottom tiling gesture, so in portrait place two windows freely, one above the other, by dragging their top edges.")
                    Text("4. Drag the divider to resize both halves; the red, yellow and green controls close, minimise and zoom a window.")
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Window Tips")
        } footer: {
            Text("iPhone-only apps stay in a phone-sized window; apps that support iPad render at tablet sizes, so wide screenshots may letterbox on a phone display.")
        }
    }

    private var applyBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "%d pending changes"), viewModel.stagedChangeCount))
                    .font(.subheadline.weight(.semibold))
                Text("Automatic backup before writing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply") { viewModel.applySelectedTweaks() }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct PlacardPromotionLink: View {
    private let placardURL = URL(string: "https://github.com/frs0n/placard")!

    var body: some View {
        Link(destination: placardURL) {
            HStack(spacing: 12) {
                placardIcon
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Placard")
                        .font(.body.weight(.medium))
                    Text("iPhone 动态壁纸")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(minHeight: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Placard，iPhone 动态壁纸，点击打开 GitHub")
    }

    private var placardIcon: Image {
        guard let url = Bundle.main.url(forResource: "PlacardIcon", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else {
            return Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled")
        }
        return Image(uiImage: image)
    }
}

private struct DeveloperFooter: View {
    private let douyinURL = URL(string: "https://v.douyin.com/hHHMAlF5bE0/")!

    var body: some View {
        Link(destination: douyinURL) {
            HStack(spacing: 12) {
                avatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                Text("SUSS")
                    .font(.subheadline.weight(.medium))

                Spacer()
            }
            .frame(minHeight: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("开发者 SUSS，点击打开抖音")
    }

    private var avatarImage: Image {
        guard let url = Bundle.main.url(forResource: "SUSSAvatar", withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else {
            return Image(systemName: "person.crop.circle")
        }
        return Image(uiImage: image)
    }
}

private struct RewardCodeView: View {
    private let rewardCodeImage: UIImage = {
        let imageURL = Bundle.main.url(forResource: "RewardCode", withExtension: "jpg")!
        return UIImage(contentsOfFile: imageURL.path)!
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(uiImage: rewardCodeImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    .accessibilityLabel("SUSS Reward Code")

                Text("感谢你对 SUSS 的支持")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("打开微信扫描上方赞赏码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("打赏 SUSS")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TweakToggle: View {
    let definition: GestaltTweakDefinition
    @Binding var isOn: Bool
    let isApplied: Bool
    let isPending: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(definition.title)
                    if definition.isRisky {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("High Risk")
                    }
                    if isPending {
                        Text("Pending")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    } else if isApplied {
                        Text("Applied")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                }
                Text(definition.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BackupLibrary: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @State private var backupToRestore: GestaltBackup?
    @State private var showsBackupImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        viewModel.createBackup()
                    } label: {
                        Label("Back Up Current MobileGestalt", systemImage: "plus.circle.fill")
                    }
                    .disabled(viewModel.plist == nil || viewModel.isBusy)

                    Button {
                        showsBackupImporter = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.isBusy)
                } footer: {
                    Text("Importing only adds a file to the backup library. It does not write immediately. The original plist is also backed up before every write.")
                }

                Section("Local Backups") {
                    if viewModel.backups.isEmpty {
                        Label("No Backups", systemImage: "archivebox")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.backups) { backup in
                            BackupRow(
                                backup: backup,
                                restore: { backupToRestore = backup },
                                restoreChange: { change in
                                    viewModel.restoreChange(change, from: backup)
                                }
                            )
                        }
                        .onDelete { offsets in
                            // Resolve every index before deleting: `delete` refreshes
                            // the backing array, so deleting by index inside the loop
                            // hits stale positions or crashes.
                            let selected = offsets.compactMap { index in
                                viewModel.backups.indices.contains(index) ? viewModel.backups[index] : nil
                            }
                            viewModel.delete(selected)
                        }
                    }
                }
            }
            .navigationTitle("Restore")
            .refreshable { viewModel.refreshBackups() }
            .onAppear { viewModel.refreshBackups() }
            .fileImporter(
                isPresented: $showsBackupImporter,
                allowedContentTypes: [.propertyList],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { viewModel.importBackup(from: url) }
                case .failure(let error):
                    viewModel.notice = GestaltNotice(kind: .error, message: error.localizedDescription)
                }
            }
            .confirmationDialog(
                "Restore This MobileGestalt Backup?",
                isPresented: Binding(
                    get: { backupToRestore != nil },
                    set: { if !$0 { backupToRestore = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Restore and Write", role: .destructive) {
                    if let backupToRestore { viewModel.restore(backupToRestore) }
                    backupToRestore = nil
                }
                Button("Cancel", role: .cancel) { backupToRestore = nil }
            } message: {
                Text("The current file will be backed up first. SpringBoard will refresh automatically after restoring.")
            }
        }
    }
}

private struct BackupRow: View {
    let backup: GestaltBackup
    let restore: () -> Void
    let restoreChange: (BackupChange) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(backup.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                    Text(ByteCountFormatter.string(fromByteCount: backup.byteCount, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if backup.isManual {
                        Text("Manual")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    if let changes = backup.changes {
                        Button {
                            withAnimation { isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                Text(changes.total == 0
                                     ? String(localized: "No changes detected")
                                     : changes.summary)
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Show change details")
                    } else {
                        Text("No change log")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                ShareLink(item: backup.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export Backup")
                Button("Restore", action: restore)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel("Restore Backup")
            }

            if isExpanded, let changes = backup.changes, !changes.changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(changes.changes) { change in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(change.key)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text(change.detail)
                                    .font(.caption2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            Button {
                                restoreChange(change)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Restore this field from the backup")
                        }
                    }
                    if changes.truncated {
                        Text(
                            String(
                                format: String(localized: "Showing the first %lld changes only."),
                                GestaltChangeDiff.limit
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 6)
            }
        }
    }
}

private struct AdvancedGestaltEditor: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @State private var activeEditor: FieldEditorRoute?
    @State private var selectedSection: EditorSection?

    private var groupedCacheExtra: [(category: GestaltKeyCategory, keys: [String])] {
        let keys = filtered(viewModel.plist?.cacheExtraKeys ?? [], section: .cacheExtra)
        var buckets: [GestaltKeyCategory: [String]] = [:]
        for key in keys {
            buckets[GestaltKeyCatalog.category(for: key), default: []].append(key)
        }
        return GestaltKeyCategory.allCases.compactMap { category in
            guard let list = buckets[category], !list.isEmpty else { return nil }
            return (category, list.sorted { GestaltKeyCatalog.sortKey($0) < GestaltKeyCatalog.sortKey($1) })
        }
    }

    private var topLevelKeys: [String] {
        filtered(
            viewModel.plist?.topLevelKeys.filter { $0 != "CacheExtra" } ?? [],
            section: .topLevel
        )
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                stackedLayout
            }
        }
    }

    /// iPad / regular width: categories in the sidebar, fields of the selected
    /// category on the right, so long lists stop pushing the header off-screen.
    private var splitLayout: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section(String(localized: "CacheExtra")) {
                    ForEach(groupedCacheExtra, id: \.category) { group in
                        Label(group.category.title, systemImage: "square.stack.3d.up")
                            .tag(Optional(EditorSection.category(group.category)))
                    }
                }
                Section {
                    Label(String(localized: "Top Level"), systemImage: "list.bullet.rectangle")
                        .tag(Optional(EditorSection.topLevel))
                }
            }
            .navigationTitle("Fields")
            .searchable(text: $searchText, prompt: "Search key or value")
            .onAppear {
                if selectedSection == nil {
                    selectedSection = groupedCacheExtra.first.map { .category($0.category) }
                }
            }
        } detail: {
            List {
                if viewModel.plist == nil {
                    Text("Reading MobileGestalt…")
                        .foregroundStyle(.secondary)
                } else {
                    switch selectedSection {
                    case .category(let category):
                        let keys = groupedCacheExtra.first { $0.category == category }?.keys ?? []
                        if keys.isEmpty {
                            Text("No Results").foregroundStyle(.secondary)
                        } else {
                            ForEach(keys, id: \.self) { key in
                                let reference = PlistKey(section: .cacheExtra, key: key)
                                Button {
                                    activeEditor = .edit(reference)
                                } label: {
                                    KeyRow(key: key, value: value(for: reference))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    case .topLevel, .none:
                        if topLevelKeys.isEmpty {
                            Text("No Results").foregroundStyle(.secondary)
                        } else {
                            ForEach(topLevelKeys, id: \.self) { key in
                                let reference = PlistKey(section: .topLevel, key: key)
                                Button {
                                    activeEditor = .edit(reference)
                                } label: {
                                    KeyRow(key: key, value: value(for: reference))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Advanced Field Editor"))
            .toolbar { editorToolbar }
        }
        .sheet(item: $activeEditor) { editor in
            editorSheet(editor)
        }
    }

    private var stackedLayout: some View {
        List {
            if viewModel.plist != nil {
                Section {
                    Text("CacheExtra keys are Apple's encrypted short codes. Fields below are grouped by what they do; keys that are not in the catalog are marked as unknown, so check a backup before changing them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(groupedCacheExtra, id: \.category) { group in
                    Section(group.category.title) {
                        ForEach(group.keys, id: \.self) { key in
                            let reference = PlistKey(section: .cacheExtra, key: key)
                            Button {
                                activeEditor = .edit(reference)
                            } label: {
                                KeyRow(key: key, value: value(for: reference))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(String(localized: "Top Level")) {
                    if topLevelKeys.isEmpty {
                        Text("No Results")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topLevelKeys, id: \.self) { key in
                            let reference = PlistKey(section: .topLevel, key: key)
                            Button {
                                activeEditor = .edit(reference)
                            } label: {
                                KeyRow(key: key, value: value(for: reference))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Advanced Field Editor")
        .searchable(text: $searchText, prompt: "Search key or value")
        .toolbar { editorToolbar }
        .sheet(item: $activeEditor) { editor in
            editorSheet(editor)
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                activeEditor = .addCacheExtra
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add CacheExtra Field")
            .disabled(viewModel.plist == nil || viewModel.isBusy)

            Button("Save", action: viewModel.applyChanges)
                .fontWeight(.semibold)
                .disabled(!viewModel.isDirty || viewModel.isBusy)
        }
    }

    @ViewBuilder
    private func editorSheet(_ editor: FieldEditorRoute) -> some View {
        Group {
            switch editor {
            case .edit(let key):
                ValueEditor(
                    key: key.key,
                    info: GestaltKeyCatalog.info(for: key.key),
                    initialValue: value(for: key),
                    save: { update($0, for: key) },
                    delete: key.section == .cacheExtra
                        ? { deleteCacheExtraField(key.key) }
                        : nil
                )
            case .addCacheExtra:
                AddCacheExtraFieldEditor(save: addCacheExtraField)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func filtered(_ keys: [String], section: PlistSection) -> [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return keys }

        return keys.filter { key in
            // Cheap checks first: key, then the catalog text. Only fall back to
            // summarizing the value (which may encode a large Data blob) when the
            // query could plausibly match it.
            if key.localizedCaseInsensitiveContains(query) { return true }
            if let knowledge = GestaltKeyCatalog.info(for: key),
               knowledge.title.localizedCaseInsensitiveContains(query)
                || knowledge.summary.localizedCaseInsensitiveContains(query) {
                return true
            }
            let reference = PlistKey(section: section, key: key)
            return PlistValueInfo.info(for: value(for: reference))
                .searchText
                .localizedCaseInsensitiveContains(query)
        }
    }

    private func value(for key: PlistKey) -> Any? {
        switch key.section {
        case .cacheExtra:
            viewModel.plist?.cacheExtra[key.key]
        case .topLevel:
            viewModel.plist?.value(forKey: key.key)
        }
    }

    private func update(_ value: Any, for key: PlistKey) {
        guard var plist = viewModel.plist else { return }
        switch key.section {
        case .cacheExtra:
            plist.setCacheExtra(value, forKey: key.key)
        case .topLevel:
            plist.setValue(value, forKey: key.key)
        }
        viewModel.plist = plist
        viewModel.isDirty = true
    }

    private func addCacheExtraField(key: String, value: Any) throws {
        guard var plist = viewModel.plist else { return }
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw AddFieldError.emptyKey
        }
        guard plist.cacheExtra[normalizedKey] == nil else {
            throw AddFieldError.duplicateKey(normalizedKey)
        }

        plist.setCacheExtra(value, forKey: normalizedKey)
        viewModel.plist = plist
        viewModel.isDirty = true
    }

    private func deleteCacheExtraField(_ key: String) {
        guard var plist = viewModel.plist else { return }
        plist.removeCacheExtraValue(forKey: key)
        viewModel.plist = plist
        viewModel.isDirty = true
    }
}

private enum PlistSection: String {
    case cacheExtra
    case topLevel
}

/// Sidebar entries of the split field editor.
private enum EditorSection: Hashable {
    case category(GestaltKeyCategory)
    case topLevel
}

private struct PlistKey: Identifiable {
    let section: PlistSection
    let key: String
    var id: String { "\(section.rawValue)/\(key)" }
}

private enum FieldEditorRoute: Identifiable {
    case edit(PlistKey)
    case addCacheExtra

    var id: String {
        switch self {
        case .edit(let key): "edit/\(key.id)"
        case .addCacheExtra: "add/cacheExtra"
        }
    }
}

private enum AddFieldError: LocalizedError {
    case emptyKey
    case duplicateKey(String)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            String(localized: "Key cannot be empty.")
        case .duplicateKey(let key):
            String(format: String(localized: "CacheExtra already contains the field: %@"), key)
        }
    }
}

private struct KeyRow: View {
    let key: String
    let value: Any?

    var body: some View {
        let info = PlistValueInfo.info(for: value)
        let knowledge = GestaltKeyCatalog.info(for: key)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(knowledge?.title ?? String(localized: "Unknown field"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if knowledge?.risk == .risky {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if let knowledge {
                    Text(knowledge.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(key)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(info.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct ValueEditor: View {
    @Environment(\.dismiss) private var dismiss

    let key: String
    let info: GestaltKeyInfo?
    let initialValue: Any?
    let save: (Any) -> Void
    let delete: (() -> Void)?

    @State private var kind: PlistValueKind
    @State private var text: String
    @State private var errorMessage: String?
    @State private var showsDeleteConfirmation = false

    init(
        key: String,
        info: GestaltKeyInfo? = nil,
        initialValue: Any?,
        save: @escaping (Any) -> Void,
        delete: (() -> Void)? = nil
    ) {
        self.key = key
        self.info = info
        self.initialValue = initialValue
        self.save = save
        self.delete = delete
        let kind = PlistValueKind.kind(of: initialValue)
        _kind = State(initialValue: kind)
        _text = State(initialValue: PlistValueInfo.encode(initialValue, as: kind))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let info {
                        Text(info.title)
                            .font(.headline)
                        Text(info.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: info.risk == .safe
                                ? "checkmark.seal"
                                : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(info.risk == .safe ? .green : .orange)
                            Text(info.risk.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Unknown field")
                            .font(.headline)
                        Text("This key is not in the built-in catalog. Its name is an encrypted MobileGestalt code, so its effect is unknown; export a backup before changing it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Raw key") {
                        Text(key)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button {
                        UIPasteboard.general.string = key
                    } label: {
                        Label("Copy Key", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("About This Field")
                }

                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(PlistValueKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Value") {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if delete != nil {
                    Section {
                        Button("Delete Field", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(key)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done", action: commit)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete CacheExtra Field?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    delete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The field will be removed from the file after you return to the editor and tap Save.")
            }
        }
    }

    private func commit() {
        do {
            save(try PlistValueInfo.parse(text, as: kind))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddCacheExtraFieldEditor: View {
    @Environment(\.dismiss) private var dismiss

    let save: (String, Any) throws -> Void

    @State private var key = ""
    @State private var kind: PlistValueKind = .string
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Field") {
                    LabeledContent("Location", value: "CacheExtra")
                    TextField("Key", text: $key)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(PlistValueKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Value") {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add", action: commit)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func commit() {
        do {
            let value = try PlistValueInfo.parse(text, as: kind)
            try save(key, value)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(GestaltViewModel())
}
