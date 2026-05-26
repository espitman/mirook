import type { EpubBlock, EpubPage, TranslatedTextPage } from "./types";

export type DisplayBlock =
  | { type: "text"; text: string }
  | { type: "link"; title: string; href: string }
  | { type: "image"; src: string; altText?: string | null };

export interface PairedDisplayRow {
  source?: DisplayBlock;
  translation?: DisplayBlock;
}

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
  const paragraphBlocks = page?.paragraphBlocks ?? [];
  const hasReliableParagraphBlocks =
    paragraphBlocks.length > 0 &&
    paragraphBlocks.every((block) => block.confidence === undefined || block.confidence >= 0.95);

  const blockParagraphs = hasReliableParagraphBlocks
    ? paragraphBlocks
      ?.map((block) => normalizeParagraphText(block.translatedText ?? ""))
      .filter((text): text is string => Boolean(text))
    : [];

  if (blockParagraphs.length) return blockParagraphs;

  return splitParagraphs(page?.translatedText ?? "", { preserveLineBreaks: true });
}

function pageSourceParagraphs(page?: TranslatedTextPage) {
  const paragraphBlocks = page?.paragraphBlocks ?? [];
  const hasReliableParagraphBlocks =
    paragraphBlocks.length > 0 &&
    paragraphBlocks.every((block) => block.confidence === undefined || block.confidence >= 0.95);

  const blockParagraphs = hasReliableParagraphBlocks
    ? paragraphBlocks
      ?.map((block) => normalizeParagraphText(block.sourceText ?? ""))
      .filter(Boolean)
    : [];

  if (blockParagraphs.length) return blockParagraphs;

  return splitParagraphs(page?.sourceText ?? "", { preserveLineBreaks: true });
}

export function pageAlignedSourceBlocks(epubPages: EpubPage[] | undefined, page?: TranslatedTextPage) {
  const pageText = page?.sourceText?.trim();
  if (!epubPages?.length || !pageText) return undefined;

  const blocks = epubPages.flatMap((epubPage) => epubPage.blocks);
  const pageMatchText = normalizeForMatch(pageText);
  const matchingIndexes = blocks
    .map((block, index) => (textBlockMatchesPage(block, pageMatchText) ? index : -1))
    .filter((index) => index >= 0);

  if (!matchingIndexes.length) return undefined;

  const bestCluster = largestContiguousCluster(matchingIndexes);
  const first = bestCluster[0];
  let last = bestCluster[bestCluster.length - 1];
  while (blocks[last + 1]?.type === "image") last += 1;
  return blocks.slice(first, last + 1);
}

export function sourceDisplayBlocks(sourceBlocks: EpubBlock[] | undefined, page?: TranslatedTextPage): DisplayBlock[] {
  const paragraphs = pageSourceParagraphs(page);
  if (!paragraphs.length) return [];
  if (!sourceBlocks?.length) return paragraphs.map((text) => ({ type: "text", text }));

  const result: DisplayBlock[] = [];
  const imagesByParagraph = imagePlacementsByParagraph(sourceBlocks, paragraphs);

  for (let paragraphIndex = 0; paragraphIndex <= paragraphs.length; paragraphIndex += 1) {
    imagesByParagraph
      .filter((placement) => placement.paragraphIndex === paragraphIndex)
      .forEach((placement) => result.push({ type: "image", src: placement.block.src, altText: placement.block.altText }));

    const text = paragraphs[paragraphIndex];
    if (text) result.push({ type: "text", text });
  }

  return result;
}

export function translatedDisplayBlocks(sourceBlocks: EpubBlock[] | undefined, page?: TranslatedTextPage): DisplayBlock[] {
  const paragraphs = translationParagraphs(page);
  if (!sourceBlocks?.length) {
    return paragraphs.map((text) => ({ type: "text", text }));
  }

  const result: DisplayBlock[] = [];
  const imagesByParagraph = imagePlacementsByParagraph(sourceBlocks, paragraphs, { scaleFallback: true });

  for (let paragraphIndex = 0; paragraphIndex <= paragraphs.length; paragraphIndex += 1) {
    imagesByParagraph
      .filter((placement) => placement.paragraphIndex === paragraphIndex)
      .forEach((placement) => result.push({ type: "image", src: placement.block.src, altText: placement.block.altText }));

    const translated = paragraphs[paragraphIndex];
    if (translated) result.push({ type: "text", text: translated });
  }

  return result;
}

export function pairedDisplayRows(sourceBlocks: EpubBlock[] | undefined, page?: TranslatedTextPage): PairedDisplayRow[] {
  const sourceParagraphs = pageSourceParagraphs(page);
  const translatedParagraphs = translationParagraphs(page);
  const sourceImages = sourceBlocks?.length ? imagePlacementsByParagraph(sourceBlocks, sourceParagraphs) : [];
  const translationImages = sourceBlocks?.length ? imagePlacementsByParagraph(sourceBlocks, translatedParagraphs, { scaleFallback: true }) : [];
  const rowCount = Math.max(sourceParagraphs.length, translatedParagraphs.length);
  const rows: PairedDisplayRow[] = [];

  for (let paragraphIndex = 0; paragraphIndex <= rowCount; paragraphIndex += 1) {
    const sourceImage = sourceImages.find((placement) => placement.paragraphIndex === paragraphIndex)?.block;
    const translationImage = translationImages.find((placement) => placement.paragraphIndex === paragraphIndex)?.block;
    const image = sourceImage ?? translationImage;
    if (image) {
      rows.push({
        source: { type: "image", src: image.src, altText: image.altText },
        translation: { type: "image", src: image.src, altText: image.altText }
      });
    }

    const sourceText = sourceParagraphs[paragraphIndex];
    const translatedText = translatedParagraphs[paragraphIndex];
    if (sourceText || translatedText) {
      rows.push({
        source: sourceText ? { type: "text", text: sourceText } : undefined,
        translation: translatedText ? { type: "text", text: translatedText } : undefined
      });
    }
  }

  return rows;
}

function imagePlacementsByParagraph(
  sourceBlocks: EpubBlock[],
  targetParagraphs: string[],
  options: { scaleFallback?: boolean } = {}
) {
  const placements: { paragraphIndex: number; block: Extract<EpubBlock, { type: "image" }> }[] = [];
  let paragraphIndex = 0;
  const sourceParagraphCount = sourceBlocks.reduce((count, block) => {
    if (block.type === "image") return count;
    return count + displayParagraphs(block.type === "link" ? block.title : block.text).length;
  }, 0);

  sourceBlocks.forEach((block, blockIndex) => {
    if (block.type === "image") {
      const referencedIndex = figureReferencePlacement(sourceBlocks, blockIndex, targetParagraphs);
      placements.push({
        paragraphIndex:
          referencedIndex ??
          fallbackImageParagraphIndex(paragraphIndex, sourceParagraphCount, targetParagraphs.length, Boolean(options.scaleFallback)),
        block
      });
      return;
    }

    paragraphIndex += displayParagraphs(block.type === "link" ? block.title : block.text).length;
  });

  return placements;
}

function fallbackImageParagraphIndex(
  sourceParagraphIndex: number,
  sourceParagraphCount: number,
  targetParagraphCount: number,
  shouldScale: boolean
) {
  if (!targetParagraphCount) return 0;
  if (!shouldScale) return Math.min(sourceParagraphIndex, targetParagraphCount);
  if (!sourceParagraphCount) return targetParagraphCount;
  return Math.min(targetParagraphCount, Math.max(0, Math.round((sourceParagraphIndex / sourceParagraphCount) * targetParagraphCount)));
}

function figureReferencePlacement(sourceBlocks: EpubBlock[], imageIndex: number, translatedParagraphs: string[]) {
  const nearbyText = sourceBlocks
    .slice(Math.max(0, imageIndex - 3), imageIndex)
    .filter((block): block is Extract<EpubBlock, { type: "text" | "link" }> => block.type !== "image")
    .map((block) => (block.type === "link" ? block.title : block.text))
    .join(" ");
  const figure = /\bfigure\s+(\d+)\s*[-–]\s*(\d+)\b/i.exec(nearbyText);
  if (!figure) return null;

  const figureNumber = `${figure[1]}-${figure[2]}`;
  const translatedIndex = translatedParagraphs.findIndex((paragraph) => normalizeFigureText(paragraph).includes(figureNumber));
  return translatedIndex >= 0 ? translatedIndex + 1 : null;
}

function normalizeFigureText(text: string) {
  return text
    .replace(/[۰-۹]/g, (digit) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(digit)))
    .replace(/[٠-٩]/g, (digit) => String("٠١٢٣٤٥٦٧٨٩".indexOf(digit)))
    .replace(/[‐‑‒–—]/g, "-");
}

function textBlockMatchesPage(block: EpubBlock, pageMatchText: string) {
  if (block.type === "image") return false;
  const blockText = normalizeForMatch(block.type === "link" ? block.title : block.text);
  if (!blockText) return false;
  if (blockText.length <= 32) return pageMatchText.includes(blockText);

  const head = blockText.slice(0, 72);
  const tail = blockText.slice(-72);
  return pageMatchText.includes(head) || pageMatchText.includes(tail);
}

function largestContiguousCluster(indexes: number[]) {
  const clusters: number[][] = [];
  let current: number[] = [];

  indexes.forEach((index) => {
    if (!current.length || index - current[current.length - 1] <= 1) {
      current.push(index);
      return;
    }
    clusters.push(current);
    current = [index];
  });
  if (current.length) clusters.push(current);

  return clusters.reduce((best, cluster) => (cluster.length > best.length ? cluster : best), clusters[0]);
}

function displayParagraphs(text: string) {
  return text
    .split(/\n{2,}/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function splitParagraphs(text: string, options: { preserveLineBreaks?: boolean } = {}) {
  const paragraphs: string[] = [];
  let currentLines: string[] = [];

  text.split(/\r?\n/).forEach((line) => {
    const trimmedLine = line.replace(/\s+$/g, "").trim();
    if (!trimmedLine) {
      if (currentLines.length) {
        paragraphs.push(currentLines.join(options.preserveLineBreaks ? "\n" : " "));
        currentLines = [];
      }
      return;
    }

    currentLines.push(trimmedLine);
  });

  if (currentLines.length) paragraphs.push(currentLines.join(options.preserveLineBreaks ? "\n" : " "));

  return options.preserveLineBreaks
    ? paragraphs.map((paragraph) => paragraph.trim()).filter(Boolean)
    : paragraphs.map(normalizeParagraphText).filter(Boolean);
}

function normalizeParagraphText(text: string) {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeForMatch(text: string) {
  return text.replace(/\s+/g, " ").trim().toLowerCase();
}
