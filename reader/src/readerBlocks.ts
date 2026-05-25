import type { EpubBlock, TranslatedTextPage } from "./types";

export type DisplayBlock =
  | { type: "text"; text: string }
  | { type: "link"; title: string; href: string }
  | { type: "image"; src: string; altText?: string | null };

export function sourcePlainText(blocks: EpubBlock[] | undefined, fallback = "") {
  const text = blocks
    ?.map((block) => {
      if (block.type === "text") return block.text;
      if (block.type === "link") return block.title;
      return "";
    })
    .filter(Boolean)
    .join("\n\n");
  return text?.trim() || fallback.trim();
}

export function translationParagraphs(page?: TranslatedTextPage) {
  const blockParagraphs =
    page?.paragraphBlocks
      ?.map((block) => block.translatedText?.trim())
      .filter((text): text is string => Boolean(text)) ?? [];

  if (blockParagraphs.length) return blockParagraphs;

  return (page?.translatedText ?? "")
    .split(/\n{2,}/)
    .map((text) => text.trim())
    .filter(Boolean);
}

export function translatedDisplayBlocks(sourceBlocks: EpubBlock[] | undefined, page?: TranslatedTextPage): DisplayBlock[] {
  const paragraphs = translationParagraphs(page);
  if (!sourceBlocks?.length) {
    return paragraphs.map((text) => ({ type: "text", text }));
  }

  const result: DisplayBlock[] = [];
  let paragraphIndex = 0;

  sourceBlocks.forEach((block, index) => {
    if (block.type === "image") {
      if (shouldPlaceParagraphBeforeImage(sourceBlocks, index, paragraphs, paragraphIndex)) {
        result.push({ type: "text", text: paragraphs[paragraphIndex] });
        paragraphIndex += 1;
      }
      result.push({ type: "image", src: block.src, altText: block.altText });
      return;
    }

    const translated = paragraphs[paragraphIndex];
    if (!translated) return;
    paragraphIndex += 1;

    if (block.type === "link") {
      result.push({ type: "link", title: translated, href: block.href });
    } else {
      result.push({ type: "text", text: translated });
    }
  });

  while (paragraphIndex < paragraphs.length) {
    result.push({ type: "text", text: paragraphs[paragraphIndex] });
    paragraphIndex += 1;
  }

  return result;
}

function shouldPlaceParagraphBeforeImage(
  sourceBlocks: EpubBlock[],
  index: number,
  paragraphs: string[],
  paragraphIndex: number
) {
  if (!paragraphs[paragraphIndex]) return false;
  const previous = sourceBlocks[index - 1];
  const next = sourceBlocks[index + 1];
  return previous?.type !== "text" && next?.type === "text";
}
