import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTargetLanguage") private var defaultTargetLanguage = "Persian"
    @AppStorage("defaultModelName") private var defaultModelName = ""

    var body: some View {
        Form {
            TextField("Default target language", text: $defaultTargetLanguage)
            TextField("OpenAI model", text: $defaultModelName)
                .textContentType(.none)
        }
        .padding(24)
        .frame(width: 420)
    }
}
