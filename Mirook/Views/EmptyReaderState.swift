import SwiftUI

struct EmptyReaderState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image("MirookLogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 62)
                .padding(18)
                .background(MirookTheme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: MirookTheme.shadow, radius: 18, y: 8)

            Text("Open a PDF to begin")
                .font(.title3.weight(.semibold))
                .foregroundStyle(MirookTheme.ink)

            Text("Mirook will show the document here before translation.")
                .font(.subheadline)
                .foregroundStyle(MirookTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MirookTheme.readerBackground)
    }
}
