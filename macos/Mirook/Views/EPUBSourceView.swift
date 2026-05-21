import SwiftUI

struct EPUBSourceView: View {
    let page: EPUBSourcePage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let page {
                    if let title = page.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(MirookTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(page.text)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(MirookTheme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    EmptyReaderState()
                }
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 48)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(MirookTheme.paperBackground)
    }
}
