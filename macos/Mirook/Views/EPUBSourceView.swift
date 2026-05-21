import AppKit
import SwiftUI

struct EPUBSourceView: View {
    let page: EPUBSourcePage?
    var onLinkTapped: (EPUBSourceLink) -> Void = { link in
        NSWorkspace.shared.open(link.url)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Color.clear
                    .frame(height: 0)
                    .id("source-top")

                if let page {
                    ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                        EPUBSourceBlockView(block: block, onLinkTapped: onLinkTapped)
                    }
                } else {
                    EmptyReaderState()
                }
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 48)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .id(page?.id ?? -1)
        .background(MirookTheme.paperBackground)
    }
}

private struct EPUBSourceBlockView: View {
    let block: EPUBSourceBlock
    let onLinkTapped: (EPUBSourceLink) -> Void

    var body: some View {
        switch block {
        case let .text(text):
            Text(text)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(MirookTheme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .link(link):
            Button {
                onLinkTapped(link)
            } label: {
                Text(link.title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .underline()
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .help(link.url.absoluteString)
        case let .image(image):
            if let nsImage = NSImage(data: image.data) {
                VStack(spacing: 8) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if let altText = image.altText {
                        Text(altText)
                            .font(.caption)
                            .foregroundStyle(MirookTheme.mutedInk)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 8)
            } else if let altText = image.altText {
                Text(altText)
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
