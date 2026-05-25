export type SourceDocumentKind = "pdf" | "epub";

export interface BookManifest {
  id: string;
  sourcePath?: string;
  displayName: string;
  pageCount: number;
  targetLanguage?: string;
  model?: string;
  createdAt?: string;
  updatedAt?: string;
  sourceFingerprint?: string | null;
  sourceKind?: SourceDocumentKind | string;
}

export interface TranslatedTextParagraphBlock {
  id: string;
  sourceText?: string;
  translatedText?: string;
  role?: string;
  confidence?: number;
}

export interface TranslatedTextPage {
  pageIndex: number;
  sourceText?: string;
  translatedText?: string;
  isBlank?: boolean;
  paragraphBlocks?: TranslatedTextParagraphBlock[];
  paragraphLayoutVersion?: number;
}

export type EpubBlock =
  | { type: "text"; text: string }
  | { type: "link"; title: string; href: string }
  | { type: "image"; src: string; mimeType: string; altText?: string | null };

export interface EpubPage {
  index: number;
  title?: string | null;
  blocks: EpubBlock[];
}

export interface MirookBookPayload {
  id: string;
  filePath: string;
  manifest: BookManifest;
  pages: TranslatedTextPage[];
  epubPages: EpubPage[];
  sourcePdf: string | null;
}

export interface MirookBridge {
  openBook: () => Promise<MirookBookPayload | null>;
  openBookPath: (filePath: string) => Promise<MirookBookPayload>;
}
