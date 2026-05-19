import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            HSplitView {
                ReaderView()
                    .frame(minWidth: 560)

                TranslationInspectorView()
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .alert("Unable to Open PDF", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                documentStore.lastErrorMessage = nil
            }
        } message: {
            Text(documentStore.lastErrorMessage ?? "Unknown error.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { documentStore.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    documentStore.lastErrorMessage = nil
                }
            }
        )
    }
}
