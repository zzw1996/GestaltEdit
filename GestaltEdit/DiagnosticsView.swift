import SwiftUI
import UIKit

/// Read-only snapshot the user can copy when a read or write fails, so a
/// signature/permission problem can be told apart from a malformed plist.
struct DiagnosticsView: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @State private var showsCopied = false

    var body: some View {
        List {
            Section {
                Text(viewModel.diagnosticsReport)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Report")
            } footer: {
                Text("Copy this when reporting a problem: it shows what the app could read, where the device class lives, and the last error message.")
            }

            Section {
                Button {
                    UIPasteboard.general.string = viewModel.diagnosticsReport
                    showsCopied = true
                } label: {
                    Label("Copy Report", systemImage: "doc.on.doc")
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Copied", isPresented: $showsCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The report is on the clipboard.")
        }
    }
}
