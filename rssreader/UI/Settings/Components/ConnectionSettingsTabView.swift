import SwiftUI
import CloudKit

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

    @State private var iCloudAccountStatus: CKAccountStatus = .couldNotDetermine

    var body: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 14) {
            iCloudStatusSection
            connectionSection
            diagnosticsSection

            Text("The Google Reader-compatible API must be enabled in your FreshRSS instance under Administration -> Authentication.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            iCloudAccountStatus = (try? await CKContainer(identifier: CloudKitSyncService.containerIdentifier).accountStatus()) ?? .couldNotDetermine
        }
#else
        Form {
            iCloudStatusSection
            connectionSection
            diagnosticsSection
        }
        .formStyle(.grouped)
        .task {
            iCloudAccountStatus = (try? await CKContainer(identifier: CloudKitSyncService.containerIdentifier).accountStatus()) ?? .couldNotDetermine
        }
#if os(macOS)
        .padding()
#endif
#endif
    }

    @ViewBuilder
    private var connectionSection: some View {
#if os(macOS)
        SettingsCard(
            title: "FreshRSS Connection",
            subtitle: "Server URL and username sync through iCloud"
        ) {
            credentialsContent
        }
#else
        Section {
            credentialsContent
        } header: {
            Text("FreshRSS Connection")
                .font(.headline)
        } footer: {
            Text("Your password stays in Keychain, and your server URL and username sync through iCloud when available. The Google Reader-compatible API must be enabled in your FreshRSS instance under Administration -> Authentication.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
#endif
    }

    @ViewBuilder
    private var iCloudStatusSection: some View {
#if os(macOS)
        SettingsCard(title: "iCloud Sync", subtitle: nil) {
            iCloudStatusContent
        }
#else
        Section("iCloud Sync") {
            iCloudStatusContent
        }
#endif
    }

    @ViewBuilder
    private var iCloudStatusContent: some View {
        connectionFieldRow("Account") {
            HStack(spacing: 6) {
                Image(systemName: iCloudAccountStatus == .available ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(iCloudAccountStatus == .available ? Color.green : Color.secondary)
                Text(iCloudStatusLabel)
                    .font(.caption)
                    .foregroundStyle(iCloudAccountStatus == .available ? Color.primary : Color.secondary)
            }
        }
    }

    private var iCloudStatusLabel: String {
        switch iCloudAccountStatus {
        case .available:          return "Signed in"
        case .noAccount:          return "Not signed in to iCloud"
        case .restricted:         return "iCloud access restricted"
        case .temporarilyUnavailable: return "iCloud temporarily unavailable"
        case .couldNotDetermine:  return "Checking…"
        @unknown default:         return "Unknown"
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
#if os(macOS)
        SettingsCard(
            title: "Diagnostics",
            subtitle: "Use these tools to validate connectivity"
        ) {
            diagnosticsContent
        }
#else
        Section("Diagnostics") {
            diagnosticsContent
        }
#endif
    }

    @ViewBuilder
    private var credentialsContent: some View {
        connectionFieldRow("Server URL") {
            TextField(serverURLPlaceholder, text: $url)
            .textContentType(.URL)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
        }

        settingsDivider

        connectionFieldRow("Username") {
            TextField("", text: $username)
            .textContentType(.username)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }

        settingsDivider

        connectionFieldRow("Password") {
            SecureField("", text: $password)
            .textContentType(.password)
                .textFieldStyle(.roundedBorder)
        }

        settingsDivider

        HStack {
            Spacer()

            Button("Save", action: saveAndDismiss)
                .buttonStyle(.borderedProminent)
#if os(macOS)
                .controlSize(.large)
#endif
                .disabled(url.isEmpty || username.isEmpty || password.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder
    private func connectionFieldRow<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
#if os(macOS)
        SettingsFieldRow(title: title, content: field)
#else
        LabeledContent(title) {
            field()
        }
#endif
    }

    @ViewBuilder
    private var diagnosticsContent: some View {
        HStack(spacing: 10) {
            Button(isTesting ? "Testing..." : "Test Connection") {
                Task { await testConnection() }
            }
#if os(macOS)
            .buttonStyle(.bordered)
#endif
            .disabled(isTesting || url.isEmpty || username.isEmpty || password.isEmpty)

            if isTesting {
                diagnosticsProgress
            }

            if let testResult {
                resultLabel(testResult)
            }
        }

        settingsDivider

        connectionFieldRow("Normalized URL") {
            Text(service.normalizedServerURL.isEmpty ? "-" : service.normalizedServerURL)
                .font(.caption)
                .textSelection(.enabled)
        }

        settingsDivider

        connectionFieldRow("Resolved Host") {
            Text(service.lastResolvedHost.isEmpty ? "-" : service.lastResolvedHost)
                .font(.caption)
                .textSelection(.enabled)
        }

        settingsDivider

        connectionFieldRow("Last URL Error") {
            Text(service.lastURLErrorCode.map(String.init) ?? "none")
                .font(.caption)
                .textSelection(.enabled)
        }

        settingsDivider

        HStack(spacing: 10) {
            Button(isRunningDNSCheck ? "Checking DNS..." : "Run DNS Check") {
                Task { await runDNSCheck() }
            }
#if os(macOS)
            .buttonStyle(.bordered)
#endif
            .disabled(isRunningDNSCheck || url.isEmpty)

            if isRunningDNSCheck {
                diagnosticsProgress
            }

            if let dnsResult {
                resultLabel(dnsResult)
            }
        }
    }

    @ViewBuilder
    private var settingsDivider: some View {
#if os(macOS)
        Divider()
#endif
    }

    @ViewBuilder
    private var diagnosticsProgress: some View {
#if os(macOS)
        ProgressView()
            .controlSize(.small)
#else
        ProgressView()
            .scaleEffect(0.7)
#endif
    }

    private var serverURLPlaceholder: String {
#if os(macOS)
        "https://rss.example.com"
#else
        ""
#endif
    }
}
