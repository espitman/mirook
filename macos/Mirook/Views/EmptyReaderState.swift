import SwiftUI

struct EmptyReaderState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image("MirookLogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 74, height: 74)
                .frame(width: 112, height: 112)
                .background(MirookTheme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: MirookTheme.shadow, radius: 18, y: 8)

            Text("Open a book to begin")
                .font(.title3.weight(.semibold))
                .foregroundStyle(MirookTheme.ink)

            Text("Mirook will show the source book here before translation.")
                .font(.subheadline)
                .foregroundStyle(MirookTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MirookTheme.readerBackground)
    }
}
