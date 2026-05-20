import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 280)
                .background(MirookTheme.sidebarBackground)

            Rectangle()
                .fill(MirookTheme.separator)
                .frame(width: 1)

            ReaderView()
                .frame(minWidth: 560)

            Rectangle()
                .fill(MirookTheme.separator)
                .frame(width: 1)

            TranslationInspectorView()
                .frame(width: 360)
        }
        .background(MirookTheme.appBackground)
        .preferredColorScheme(.light)
        .frame(minWidth: 1120, minHeight: 720)
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
