import SwiftUI

@main
struct MirookApp: App {
    @StateObject private var documentStore = PDFDocumentStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(documentStore)
                .onOpenURL { url in
                    Task { @MainActor in
                        documentStore.openDroppedDocument(from: url)
                    }
                }
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
        }
    }
}
