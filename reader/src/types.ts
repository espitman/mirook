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
  fingerprint: string;
  filePath: string;
  manifest: BookManifest;
  pages: TranslatedTextPage[];
  epubPages: EpubPage[];
  sourcePdf: string | null;
  readerState?: ReaderState;
}

export interface ReadingPosition {
  book_id?: string;
  page_index?: number;
  view_mode?: string;
  font_size?: number | null;
  scroll_original?: number;
  scroll_translation?: number;
  updated_at?: string;
}

export interface ReaderState {
  position?: ReadingPosition | null;
  annotations?: ReaderAnnotation[];
  bookmarks?: unknown[];
  summaries?: ReaderSummary[];
}

export interface SaveReadingPositionInput {
  bookId: string;
  pageIndex: number;
  viewMode: string;
  fontSize: number;
  scrollOriginal?: number;
  scrollTranslation?: number;
}

export type AnnotationSide = "original" | "translation";

export interface ReaderAnnotation {
  id: string;
  book_id: string;
  page_index: number;
  side: AnnotationSide;
  block_id: string;
  start_offset: number;
  end_offset: number;
  selected_text: string;
  color?: string | null;
  note?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface SaveAnnotationInput {
  id?: string;
  bookId: string;
  pageIndex: number;
  side: AnnotationSide;
  blockId: string;
  startOffset: number;
  endOffset: number;
  selectedText: string;
  color?: string;
  note?: string | null;
}

export interface LiaraAiSettings {
  url: string;
  apiKey: string;
  model: string;
}

export interface ReaderSummary {
  id: string;
  book_id: string;
  start_page: number;
  end_page: number;
  model: string;
  summary: string;
  output_type?: "summary" | "notes" | string;
  title?: string | null;
  input_tokens?: number;
  output_tokens?: number;
  total_tokens?: number;
  provider_cost?: number | null;
  cost_currency?: string | null;
  created_at?: string;
}

export interface SummarizePagesInput {
  bookId: string;
  startPage: number;
  endPage: number;
  text: string;
}

export interface GenerateTextFromNotesInput {
  bookId: string;
  startPage: number;
  endPage: number;
  text: string;
}

export interface MirookBridge {
  openBook: () => Promise<MirookBookPayload | null>;
  openBookPath: (filePath: string) => Promise<MirookBookPayload>;
  getPathForFile: (file: File) => string;
  toggleWindowZoom: () => Promise<boolean>;
  saveReadingPosition: (position: SaveReadingPositionInput) => Promise<boolean>;
  exportBookData: (bookId: string) => Promise<string | null>;
  saveAnnotation: (annotation: SaveAnnotationInput) => Promise<ReaderAnnotation>;
  deleteAnnotation: (id: string) => Promise<boolean>;
  summarizePages: (request: SummarizePagesInput) => Promise<ReaderSummary>;
  generateTextFromNotes: (request: GenerateTextFromNotesInput) => Promise<ReaderSummary>;
  deleteAiOutput: (id: string) => Promise<boolean>;
  getAiSettings: () => Promise<LiaraAiSettings>;
  saveAiSettings: (settings: LiaraAiSettings) => Promise<LiaraAiSettings>;
}
