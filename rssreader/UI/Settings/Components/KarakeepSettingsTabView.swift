import SwiftUI

struct KarakeepSettingsTabView: View {
    @ObservedObject var service: KarakeepService
    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        #if os(macOS)
        SettingsCard(title: "Karakeep", subtitle: "Save articles to your bookmark library") {
            settingsContent
        }
        .onAppear(perform: loadSettings)
        #else
        Form {
            Section("Karakeep") {
                settingsContent
            }
        }
        .onAppear(perform: loadSettings)
        #endif
    }

    @ViewBuilder
    private var settingsContent: some View {
        LabeledContent("Server URL") {
            TextField("https://karakeep.example.com", text: $serverURL)
                .textContentType(.URL)
                .plainTextInput(isURL: true)
                .textFieldStyle(.roundedBorder)
        }
        LabeledContent("API Key") {
            SecureField("API Key", text: $apiKey)
                .plainTextInput()
                .textFieldStyle(.roundedBorder)
        }
        Text("Create an API key in Karakeep Settings > API Keys. The key is stored in Keychain. Use your server's base URL, not its /api path.")
            .font(.caption)
            .foregroundStyle(.secondary)
        HStack {
            Button("Save") {
                do {
                    try service.configure(server: serverURL, apiKey: apiKey)
                    serverURL = service.serverURL
                    isError = false
                    message = "Karakeep settings saved."
                } catch {
                    isError = true
                    message = error.localizedDescription
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverURL.isEmpty || apiKey.isEmpty || service.isSaving)

            if service.isConfigured {
                Button("Disconnect", role: .destructive) {
                    do {
                        try service.disconnect()
                        serverURL = ""
                        apiKey = ""
                        isError = false
                        message = "Disconnected from Karakeep."
                    } catch {
                        isError = true
                        message = error.localizedDescription
                    }
                }
                .disabled(service.isSaving)
            }
        }
        if let message {
            Label(message, systemImage: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(isError ? Color.red : Color.secondary)
        }
    }

    private func loadSettings() {
        serverURL = service.serverURL
        do {
            apiKey = try service.loadAPIKey()
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }
}
