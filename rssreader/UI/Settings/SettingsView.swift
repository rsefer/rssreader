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

    private var allTabs: [SettingsTab] {
        SettingsTab.allCases
    }

    private var currentTabIndex: Int? {
        allTabs.firstIndex(of: selectedTab)
    }

    private var isFirstTab: Bool {
        currentTabIndex == 0
    }

    private var isLastTab: Bool {
        currentTabIndex == allTabs.count - 1
    }

    enum SettingsTab: Hashable {
        case read
        case connection
        case autoRefresh

        var title: String {
            switch self {
            case .read:
                return "Reading"
            case .connection:
                return "Connection"
            case .autoRefresh:
                return "Auto Refresh"
            }
        }

        var subtitle: String {
            switch self {
            case .read:
                return "Article thumbnails and browsing"
            case .connection:
                return "FreshRSS account and diagnostics"
            case .autoRefresh:
                return "Background sync behavior"
            }
        }

        var symbol: String {
            switch self {
            case .read:
                return "book.closed"
            case .connection:
                return "network"
            case .autoRefresh:
                return "arrow.triangle.2.circlepath"
            }
        }
    }

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
#if os(macOS)
        macSettingsLayout
//            .frame(minWidth: 880, minHeight: 600)
        .onAppear {
            selectedTab = .connection
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
            selectedTab = .connection
            url      = service.serverURL
            username = service.username
            password = service.password
        }
#endif
    }

#if os(macOS)
    private var macSettingsLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    Image(systemName: tab.symbol)
                        .symbolRenderingMode(.monochrome)
                        .frame(width: 18)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectedTabContent
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ControlGroup {
                    Button(action: navigateBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(isFirstTab)

                    Button(action: navigateForward) {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .disabled(isLastTab)
                }
                .controlGroupStyle(.navigation)
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .read:
            ReadingSettingsTabView()
        case .connection:
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
        case .autoRefresh:
            AutoRefreshSettingsTabView()
        }
    }
#endif

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

    private func navigateBack() {
        guard let index = currentTabIndex, index > 0 else { return }
        selectedTab = allTabs[index - 1]
    }

    private func navigateForward() {
        guard let index = currentTabIndex, index < allTabs.count - 1 else { return }
        selectedTab = allTabs[index + 1]
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

extension SettingsView.SettingsTab: CaseIterable {}

private struct SettingsPreviewHost: View {
		@StateObject private var service = AppBootstrap.makeService()

		var body: some View {
				SettingsView()
						.environmentObject(service)
		}
}

#Preview("SettingsView") {
		SettingsPreviewHost()
}
