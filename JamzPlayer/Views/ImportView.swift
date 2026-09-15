import SwiftUI

struct ImportView: View {
    let isImporting: Bool
    let progress: Double?
    let status: String
    let onImport: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/song.mp3", text: $address)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .disabled(isImporting)
                        .accessibilityLabel("MP3 下載網址")
                } header: {
                    Text("音樂網址")
                } footer: {
                    Text("貼上 HTTPS MP3 直連網址。下載後儲存在手機，即使離線也能聆聽。")
                }
                if isImporting {
                    Section {
                        if let progress {
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))%")
                                .monospacedDigit()
                        } else {
                            ProgressView()
                        }
                        Text(status)
                        Button("取消匯入", role: .cancel, action: onCancel)
                    }
                } else {
                    Button("下載音樂", action: { onImport(address) })
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background { JamzBackground() }
            .navigationTitle("匯入音樂")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }.disabled(isImporting)
                }
            }
            .interactiveDismissDisabled(isImporting)
        }
    }
}
