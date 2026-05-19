import SwiftUI

struct EmptyReaderState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Open a PDF to begin")
                .font(.title3.weight(.semibold))

            Text("Mirook will show the document here before translation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
