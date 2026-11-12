import SwiftUI

/// Model picker for identity spoofing. Only identity strings are rewritten, so
/// the picker is explicit about what does and does not change.
struct DeviceSpoofView: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showIPads = false
    @State private var pendingTarget: DeviceSpoofTarget?

    private var targets: [DeviceSpoofTarget] {
        let all = AIRegionProfile.spoofTargets
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { target in
            guard target.isIPad == showIPads else { return false }
            guard !query.isEmpty else { return true }
            return target.marketingName.localizedCaseInsensitiveContains(query)
                || target.productType.localizedCaseInsensitiveContains(query)
                || target.regulatoryModel.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Only the model name and model numbers change. The board code, CPU model and device class stay as they are, so the system still behaves like the real hardware. Face ID, OTA updates and warranty checks may still report the original device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Family", selection: $showIPads) {
                        Text("iPhone").tag(false)
                        Text("iPad").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section(String(localized: "Target Model")) {
                    ForEach(targets) { target in
                        Button {
                            pendingTarget = target
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(target.marketingName)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("\(target.productType) · \(target.regulatoryModel)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.deviceIdentity.mgProductType == target.productType {
                                    Text("Current")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Spoof Device Model")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search model or identifier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                String(localized: "Spoof this device?"),
                isPresented: Binding(
                    get: { pendingTarget != nil },
                    set: { if !$0 { pendingTarget = nil } }
                ),
                presenting: pendingTarget
            ) { target in
                Button(String(localized: "Write identity, then respring")) {
                    viewModel.spoofIdentity(as: target)
                    pendingTarget = nil
                    dismiss()
                }
                Button("Cancel", role: .cancel) { pendingTarget = nil }
            } message: { target in
                Text(String(
                    format: String(localized: "The device will report itself as %@ (%@). Use Restore Official Identity to undo this."),
                    target.marketingName,
                    target.productType
                ))
            }
        }
    }
}
