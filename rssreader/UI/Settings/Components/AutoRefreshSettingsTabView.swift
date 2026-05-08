import SwiftUI

struct AutoRefreshSettingsTabView: View {
    @EnvironmentObject private var service: FreshRSSService

    var body: some View {
        Form {
            Section("Auto Refresh") {
                Toggle("Enable automatic refresh", isOn: $service.autoRefreshEnabled)

                Stepper(value: $service.autoRefreshIntervalMinutes, in: 1...240) {
                    Text("Refresh every \(service.autoRefreshIntervalMinutes) minute\(service.autoRefreshIntervalMinutes == 1 ? "" : "s")")
                }
                .disabled(!service.autoRefreshEnabled)

                Text("When enabled, feeds sync automatically while the app is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
#if os(macOS)
        .padding()
#endif
    }
}
