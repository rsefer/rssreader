import SwiftUI

struct ConnectionSettingsTabView: View {
    @EnvironmentObject private var service: FreshRSSService

    @Binding var url: String
    @Binding var username: String
    @Binding var password: String
    @Binding var isTesting: Bool
    @Binding var isRunningDNSCheck: Bool
    @Binding var testResult: SettingsView.TestResult?
    @Binding var dnsResult: SettingsView.TestResult?

    let runDNSCheck: () async -> Void
    let testConnection: () async -> Void
    let saveAndDismiss: () -> Void
    let resultLabel: (SettingsView.TestResult) -> AnyView

    var body: some View {
        Form {
            Section {
                LabeledContent("Server URL") {
                    TextField("", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                LabeledContent("Username") {
                    TextField("", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                LabeledContent("Password") {
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()

                    Button("Save", action: saveAndDismiss)
                        .buttonStyle(.borderedProminent)
                        .disabled(url.isEmpty || username.isEmpty || password.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            } header: {
                Text("FreshRSS Connection")
                    .font(.headline)
            } footer: {
                Text("Your credentials are securely stored in your Mac's Keychain. The Google Reader-compatible API must be enabled in your FreshRSS instance under Administration -> Authentication.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                HStack {
                    Button(isTesting ? "Testing..." : "Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting || url.isEmpty || username.isEmpty || password.isEmpty)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    if let testResult {
                        resultLabel(testResult)
                    }
                }

                LabeledContent("Normalized URL") {
                    Text(service.normalizedServerURL.isEmpty ? "-" : service.normalizedServerURL)
                        .font(.caption)
                        .textSelection(.enabled)
                }

                LabeledContent("Resolved Host") {
                    Text(service.lastResolvedHost.isEmpty ? "-" : service.lastResolvedHost)
                        .font(.caption)
                        .textSelection(.enabled)
                }

                LabeledContent("Last URL Error") {
                    Text(service.lastURLErrorCode.map(String.init) ?? "none")
                        .font(.caption)
                        .textSelection(.enabled)
                }

                HStack {
                    Button(isRunningDNSCheck ? "Checking DNS..." : "Run DNS Check") {
                        Task { await runDNSCheck() }
                    }
                    .disabled(isRunningDNSCheck || url.isEmpty)

                    if isRunningDNSCheck {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    if let dnsResult {
                        resultLabel(dnsResult)
                    }
                }
            }
        }
        .formStyle(.grouped)
#if os(macOS)
        .padding()
#endif
    }
}
