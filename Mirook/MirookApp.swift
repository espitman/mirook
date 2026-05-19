import SwiftUI

@main
struct MirookApp: App {
    @StateObject private var documentStore = PDFDocumentStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(documentStore)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
        }
    }
}
