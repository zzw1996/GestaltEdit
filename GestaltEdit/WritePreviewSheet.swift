import SwiftUI

/// Key-level preview shown before a write, plus an explicit acknowledgement
/// gate for anything the catalog marks risky.
struct WritePreviewSheet: View {
    let preview: WritePreview
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgedRisks = false

    private var requiresAcknowledgement: Bool { !preview.riskyItems.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Source", value: preview.source.label)
                    LabeledContent("Added", value: "\(preview.changeSet.added)")
                    LabeledContent("Modified", value: "\(preview.changeSet.modified)")
                    LabeledContent("Removed", value: "\(preview.changeSet.removed)")
                } header: {
                    Text("Summary")
                }

                if requiresAcknowledgement {
                    Section {
                        ForEach(preview.riskyItems, id: \.self) { item in
                            Label(item, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }

                        Toggle(isOn: $acknowledgedRisks) {
                            Text("I understand these changes carry risk")
                        }
                        .accessibilityHint("Required before the write can start.")
                    } header: {
                        Text("High Risk")
                    } footer: {
                        Text("A backup of the current file is created before writing. If the write does not verify, it is rolled back automatically.")
                    }
                }

                Section {
                    if preview.changeSet.changes.isEmpty {
                        Text("No field changes.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(preview.changeSet.changes) { change in
                            changeRow(change)
                        }
                        if preview.changeSet.truncated {
                            Text("More changes than shown; the backup keeps the full list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Fields")
                }
            }
            .navigationTitle("Review Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Write") {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(requiresAcknowledgement && !acknowledgedRisks)
                }
            }
        }
    }

    private func rawKey(_ key: String) -> String {
        key.hasPrefix("CacheExtra/") ? String(key.dropFirst("CacheExtra/".count)) : key
    }

    @ViewBuilder
    private func changeRow(_ change: BackupChange) -> some View {
        let innerKey = rawKey(change.key)
        let info = GestaltKeyCatalog.info(for: innerKey)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(info?.title ?? change.key)
                    .font(.subheadline.weight(.medium))

                if info?.risk == .risky {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Risky field")
                }
            }

            if info != nil {
                Text(change.key)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(change.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
