import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTargetLanguage") private var defaultTargetLanguage = "Persian"
    @AppStorage("defaultModelName") private var defaultModelName = "gpt-5.2"
    @State private var apiKey = ""
    @State private var statusMessage: String?

    private let keychainService = KeychainService()
    private let apiKeyAccount = "openai-api-key"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Form {
                SecureField("OpenAI API key", text: $apiKey)
                    .textContentType(.password)

                TextField("Default target language", text: $defaultTargetLanguage)
                TextField("OpenAI model", text: $defaultModelName)
                    .textContentType(.none)
            }

            HStack {
                Button("Save API Key") {
                    saveAPIKey()
                }
                .buttonStyle(.borderedProminent)

                Button("Remove API Key", role: .destructive) {
                    removeAPIKey()
                }

                Spacer()
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420)
        .task {
            loadAPIKey()
        }
    }

    private func loadAPIKey() {
        do {
            apiKey = try keychainService.read(account: apiKeyAccount) ?? ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveAPIKey() {
        do {
            try keychainService.save(apiKey, account: apiKeyAccount)
            statusMessage = "API key saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func removeAPIKey() {
        do {
            try keychainService.delete(account: apiKeyAccount)
            apiKey = ""
            statusMessage = "API key removed."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
