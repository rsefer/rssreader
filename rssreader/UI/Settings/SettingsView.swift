import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var service: FreshRSSService
    @Environment(\.dismiss) private var dismiss

    @State private var url      = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var isRunningDNSCheck = false
    @State private var testResult: TestResult?
    @State private var dnsResult: TestResult?
    @State private var selectedTab: SettingsTab = .connection

    enum SettingsTab: Hashable {
        case read
        case connection
        case autoRefresh
    }

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
#if os(macOS)
        settingsTabs
            .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            url      = service.serverURL
            username = service.username
            password = service.password
        }
        .onDisappear {
            applyToService()
            Task { await service.authenticate() }
        }
#else
        NavigationStack {
            settingsTabs
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear {
            url      = service.serverURL
            username = service.username
            password = service.password
        }
#endif
    }

    private var settingsTabs: some View {
        TabView(selection: $selectedTab) {
            ReadingSettingsTabView()
                .tabItem {
                    Label("Reading", systemImage: "book")
                }
                .tag(SettingsTab.read)

            ConnectionSettingsTabView(
                url: $url,
                username: $username,
                password: $password,
                isTesting: $isTesting,
                isRunningDNSCheck: $isRunningDNSCheck,
                testResult: $testResult,
                dnsResult: $dnsResult,
                runDNSCheck: runDNSCheck,
                testConnection: testConnection,
                saveAndDismiss: saveAndDismiss,
                resultLabel: { AnyView(resultLabel($0)) }
            )
            .tabItem {
                Label("Connection", systemImage: "network")
            }
            .tag(SettingsTab.connection)

            AutoRefreshSettingsTabView()
                .tabItem {
                    Label("Auto Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsTab.autoRefresh)
        }
    }

    // MARK: - Actions

    private func saveAndDismiss() {
        applyToService()
        dismiss()
        Task { await service.authenticate() }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        applyToService()

        await service.authenticate()

        if service.isAuthenticated {
            testResult = .success("Connected — \(service.items.count) unread item(s) found.")
        } else {
            testResult = .failure(service.errorMessage ?? "Connection failed.")
        }
        isTesting = false
    }

    private func runDNSCheck() async {
        isRunningDNSCheck = true
        dnsResult = nil
        applyToService()

        let result = await service.runDNSPreflight()
        dnsResult = result.success ? .success(result.message) : .failure(result.message)
        isRunningDNSCheck = false
    }

    private func applyToService() {
        service.serverURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        service.username  = username.trimmingCharacters(in: .whitespacesAndNewlines)
        service.password  = password
    }

    @ViewBuilder
    private func resultLabel(_ result: TestResult) -> some View {
        switch result {
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
