import SwiftUI

struct AutoRefreshSettingsTabView: View {
    @EnvironmentObject private var service: FreshRSSService

    var body: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 14) {
            autoRefreshSection

            Text("Automatic refresh only runs while the app is open and active.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
#else
        Form {
            autoRefreshSection
        }
        .formStyle(.grouped)
#if os(macOS)
        .padding()
#endif
#endif
    }

    @ViewBuilder
    private var autoRefreshSection: some View {
#if os(macOS)
        SettingsCard(
            title: "Automatic Refresh",
            subtitle: "Keep feeds synced while the app is active"
        ) {
            autoRefreshContent
        }
#else
        Section("Auto Refresh") {
            autoRefreshContent
        }
#endif
    }

    @ViewBuilder
    private var autoRefreshContent: some View {
        autoRefreshRow("Enable automatic refresh") {
            Toggle("Enable automatic refresh", isOn: $service.autoRefreshEnabled)
#if os(macOS)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
#endif
        }

        autoRefreshDivider

        autoRefreshRow("Refresh interval") {
            Stepper(value: $service.autoRefreshIntervalMinutes, in: 1...240) {
                Text(autoRefreshIntervalLabel)
#if os(macOS)
                    .frame(width: 70, alignment: .trailing)
#endif
            }
            .disabled(!service.autoRefreshEnabled)
        }

#if !os(macOS)
        Text("When enabled, feeds sync automatically while the app is active.")
            .font(.caption)
            .foregroundStyle(.secondary)
#endif
    }

    @ViewBuilder
    private func autoRefreshRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
#if os(macOS)
        SettingsRow(title: title, detail: nil, content: content)
#else
        content()
#endif
    }

    @ViewBuilder
    private var autoRefreshDivider: some View {
#if os(macOS)
        Divider()
#endif
    }

    private var autoRefreshIntervalLabel: String {
#if os(macOS)
        "\(service.autoRefreshIntervalMinutes) min"
#else
        "Refresh every \(service.autoRefreshIntervalMinutes) minute\(service.autoRefreshIntervalMinutes == 1 ? "" : "s")"
#endif
    }
}
