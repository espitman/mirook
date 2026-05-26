import { useEffect, useMemo, useRef, useState } from "react";
import type { CSSProperties, FormEvent, MouseEvent as ReactMouseEvent, ReactNode } from "react";
import {
  BookOpen,
  ChevronLeft,
  ChevronRight,
  Download,
  FileText,
  FolderOpen,
  Highlighter,
  Loader2,
  MessageSquare,
  Minus,
  PanelLeftClose,
  Plus,
  Save,
  Settings,
  Sparkles,
  StickyNote,
  Trash2,
  X
} from "lucide-react";
import type { DisplayBlock } from "./readerBlocks";
import { pageAlignedSourceBlocks, sourceDisplayBlocks, sourcePlainText, translatedDisplayBlocks, translationParagraphs } from "./readerBlocks";
import type { AnnotationSide, EpubBlock, LiaraAiSettings, MirookBookPayload, ReaderAnnotation, ReaderSummary, TranslatedTextPage } from "./types";

type ViewMode = "split" | "original" | "translation";
type SelectionState = {
  x: number;
  y: number;
  pageIndex: number;
  side: AnnotationSide;
  blockId: string;
  startOffset: number;
  endOffset: number;
  selectedText: string;
};
type NotePopoverPosition = { left: number; top: number; width: number; arrowLeft: number; placement: "above" | "below" };
type NotePopoverAnchor = { x: number; y: number };
type AiDialogMode = "create" | "generated";
type AiTab = "new" | "notes";
type SettingsTab = "ai" | "data";

const HIGHLIGHT_COLORS = [
  { label: "Yellow", value: "#fde68a" },
  { label: "Green", value: "#bbf7d0" },
  { label: "Blue", value: "#bfdbfe" },
  { label: "Pink", value: "#fbcfe8" },
  { label: "Purple", value: "#ddd6fe" }
];

const AI_MODELS = [
  { label: "openai/gpt-5-nano", value: "openai/gpt-5-nano" }
];

const ORIGINAL_FONT_SIZE_STORAGE_KEY = "mirook-reader-original-font-size-v3";
const ORIGINAL_READER_FONT_SIZE = 18;
const TRANSLATION_READER_FONT_SIZE = 22;
const ORIGINAL_READER_LINE_HEIGHT = 1.5;

export function App() {
  const [book, setBook] = useState<MirookBookPayload | null>(null);
  const [pageIndex, setPageIndex] = useState(0);
  const [originalFontSize, setOriginalFontSize] = useState(() =>
    Number(localStorage.getItem(ORIGINAL_FONT_SIZE_STORAGE_KEY) ?? ORIGINAL_READER_FONT_SIZE)
  );
  const [translationFontSize, setTranslationFontSize] = useState(() =>
    Number(localStorage.getItem("mirook-reader-translation-font-size") ?? localStorage.getItem("mirook-reader-font-size") ?? TRANSLATION_READER_FONT_SIZE)
  );
  const [viewMode, setViewMode] = useState<ViewMode>("split");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [annotations, setAnnotations] = useState<ReaderAnnotation[]>([]);
  const [selection, setSelection] = useState<SelectionState | null>(null);
  const [noteDraft, setNoteDraft] = useState("");
  const [selectedHighlightColor, setSelectedHighlightColor] = useState(HIGHLIGHT_COLORS[0].value);
  const [notesColorFilter, setNotesColorFilter] = useState<string | null>(null);
  const [notesOpen, setNotesOpen] = useState(false);
  const [notesMounted, setNotesMounted] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsMounted, setSettingsMounted] = useState(false);
  const [aiSettings, setAiSettings] = useState<LiaraAiSettings>({ url: "", apiKey: "", model: AI_MODELS[0].value });
  const [aiOpen, setAiOpen] = useState(false);
  const [aiMounted, setAiMounted] = useState(false);
  const [aiDialogMode, setAiDialogMode] = useState<AiDialogMode>("create");
  const [aiMenuOpen, setAiMenuOpen] = useState(false);
  const [isSummarizing, setIsSummarizing] = useState(false);
  const [isGeneratingNotesText, setIsGeneratingNotesText] = useState(false);
  const [summaries, setSummaries] = useState<ReaderSummary[]>([]);
  const [latestSummary, setLatestSummary] = useState<ReaderSummary | null>(null);
  const [pendingDeleteAiOutputId, setPendingDeleteAiOutputId] = useState<string | null>(null);
  const [isOpening, setIsOpening] = useState(false);
  const scrollRef = useRef<HTMLDivElement | null>(null);

  const pageCount = book?.manifest.pageCount ?? 0;
  const page = useMemo(() => book?.pages.find((item) => item.pageIndex === pageIndex), [book, pageIndex]);
  const sourceBlocks = useMemo(() => pageAlignedSourceBlocks(book?.epubPages, page), [book?.epubPages, page]);
  const title = book?.manifest.displayName ?? "Mirook Reader";
  const sourceKind = String(book?.manifest.sourceKind ?? "pdf").toLowerCase();
  const hasBook = Boolean(book);
  const canGoPrevious = pageIndex > 0;
  const canGoNext = pageCount ? pageIndex < pageCount - 1 : false;

  useEffect(() => {
    localStorage.setItem(ORIGINAL_FONT_SIZE_STORAGE_KEY, String(originalFontSize));
  }, [originalFontSize]);

  useEffect(() => {
    localStorage.setItem("mirook-reader-translation-font-size", String(translationFontSize));
  }, [translationFontSize]);

  useEffect(() => {
    let isCurrent = true;
    window.mirook.getAiSettings()
      .then((settings) => {
        if (isCurrent) setAiSettings(settings);
      })
      .catch((err) => setError(errorMessage(err)));
    return () => {
      isCurrent = false;
    };
  }, []);

  useEffect(() => {
    if (settingsOpen) {
      setSettingsMounted(true);
      return;
    }
    const timeout = window.setTimeout(() => setSettingsMounted(false), 220);
    return () => window.clearTimeout(timeout);
  }, [settingsOpen]);

  useEffect(() => {
    if (notesOpen) {
      setNotesMounted(true);
      return;
    }
    const timeout = window.setTimeout(() => setNotesMounted(false), 300);
    return () => window.clearTimeout(timeout);
  }, [notesOpen]);

  useEffect(() => {
    if (!settingsOpen) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") closeSettings();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [settingsOpen]);

  useEffect(() => {
    if (!aiMenuOpen) return;
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target;
      if (target instanceof Element && target.closest("[data-ai-menu]")) return;
      setAiMenuOpen(false);
    };
    window.addEventListener("pointerdown", onPointerDown, true);
    return () => window.removeEventListener("pointerdown", onPointerDown, true);
  }, [aiMenuOpen]);

  useEffect(() => {
    if (aiOpen) {
      setAiMounted(true);
      return;
    }
    const timeout = window.setTimeout(() => setAiMounted(false), 220);
    return () => window.clearTimeout(timeout);
  }, [aiOpen]);

  useEffect(() => {
    if (!book) return;
    const timeout = window.setTimeout(() => {
      void window.mirook.saveReadingPosition({
        bookId: book.id,
        pageIndex,
        viewMode,
        fontSize: translationFontSize
      });
    }, 250);
    return () => window.clearTimeout(timeout);
  }, [book, pageIndex, viewMode, translationFontSize]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0 });
  }, [pageIndex, viewMode, book?.id]);

  useEffect(() => {
    if (!selection) return;
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target;
      if (target instanceof Element && target.closest("[data-selection-toolbar]")) return;
      setSelection(null);
      setNoteDraft("");
    };
    window.addEventListener("pointerdown", onPointerDown, true);
    return () => window.removeEventListener("pointerdown", onPointerDown, true);
  }, [selection]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!hasBook) return;
      const target = event.target;
      if (target instanceof Element && target.closest("button, a, input, select, textarea")) return;
      if (event.key === "ArrowUp" || event.key === "ArrowDown") {
        event.preventDefault();
        const direction = event.key === "ArrowDown" ? 1 : -1;
        document.querySelectorAll<HTMLElement>("[data-reader-scroll-pane]").forEach((element) => {
          element.scrollBy({ top: direction * 76, behavior: "smooth" });
        });
      }
      if (event.key === "ArrowLeft") {
        event.preventDefault();
        setPageIndex((value) => Math.max(0, value - 1));
      }
      if (event.key === "ArrowRight") {
        event.preventDefault();
        setPageIndex((value) => Math.min(pageCount - 1, value + 1));
      }
      if (event.key === "Escape") {
        event.preventDefault();
        setViewMode("split");
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [hasBook, pageCount]);

  useEffect(() => {
    const onDragOver = (event: DragEvent) => {
      event.preventDefault();
    };
    const onDrop = async (event: DragEvent) => {
      event.preventDefault();
      const file = event.dataTransfer?.files?.[0];
      const filePath = file ? window.mirook.getPathForFile(file) : "";
      if (!filePath) {
        setError("Electron could not read the dropped file path. Use Open MRBK.");
        return;
      }
      if (!filePath.toLowerCase().endsWith(".mrbk")) {
        setError("Please drop a .mrbk file.");
        return;
      }
      await openPath(filePath);
    };
    window.addEventListener("dragover", onDragOver);
    window.addEventListener("drop", onDrop);
    return () => {
      window.removeEventListener("dragover", onDragOver);
      window.removeEventListener("drop", onDrop);
    };
  }, []);

  async function openBook() {
    setIsOpening(true);
    setError(null);
    setNotice(null);
    setSelection(null);
    try {
      const payload = await window.mirook.openBook();
      if (payload) {
        applyOpenedBook(payload);
      }
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setIsOpening(false);
    }
  }

  async function openPath(path: string) {
    setIsOpening(true);
    setError(null);
    setNotice(null);
    setSelection(null);
    try {
      const payload = await window.mirook.openBookPath(path);
      applyOpenedBook(payload);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setIsOpening(false);
    }
  }

  function applyOpenedBook(payload: MirookBookPayload) {
    const savedPosition = payload.readerState?.position;
    const savedPageIndex = Number(savedPosition?.page_index);
    const savedPageCount = payload.manifest.pageCount || payload.pages.length;
    const restoredPageIndex =
      Number.isInteger(savedPageIndex) && savedPageIndex >= 0 && savedPageIndex < savedPageCount
        ? savedPageIndex
        : firstReadablePage(payload);
    const savedViewMode = savedPosition?.view_mode;
    const savedFontSize = Number(savedPosition?.font_size);

    setBook(payload);
    setAnnotations(payload.readerState?.annotations ?? []);
    setSummaries(payload.readerState?.summaries ?? []);
    setLatestSummary(null);
    setPageIndex(restoredPageIndex);
    setViewMode(isViewMode(savedViewMode) ? savedViewMode : "split");
    if (Number.isFinite(savedFontSize) && savedFontSize >= 14 && savedFontSize <= 36) {
      setTranslationFontSize(savedFontSize);
    }
  }

  async function exportBookData() {
    if (!book) return;
    setError(null);
    setNotice(null);
    try {
      const exportedPath = await window.mirook.exportBookData(book.id);
      if (exportedPath) setNotice(`Reader data exported to ${exportedPath}`);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  function handleSelectionContextMenu(side: AnnotationSide, selectedPageIndex: number, event: ReactMouseEvent<HTMLElement>) {
    const nextSelection = selectionFromWindow(side, selectedPageIndex, { x: event.clientX, y: event.clientY });
    if (!nextSelection) {
      setSelection(null);
      return;
    }
    event.preventDefault();
    setSelection(nextSelection);
    setNoteDraft("");
  }

  async function saveSelectedAnnotation(note?: string | null) {
    if (!book || !selection) return;
    setError(null);
    try {
      const saved = await window.mirook.saveAnnotation({
        bookId: book.id,
        pageIndex: selection.pageIndex,
        side: selection.side,
        blockId: selection.blockId,
        startOffset: selection.startOffset,
        endOffset: selection.endOffset,
        selectedText: selection.selectedText,
        color: selectedHighlightColor,
        note: note?.trim() || null
      });
      setAnnotations((items) => [saved, ...items.filter((item) => item.id !== saved.id)]);
      setSelection(null);
      setNoteDraft("");
      window.getSelection()?.removeAllRanges();
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function deleteAnnotation(id: string) {
    setError(null);
    try {
      await window.mirook.deleteAnnotation(id);
      setAnnotations((items) => items.filter((item) => item.id !== id));
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function saveAiSettings(nextSettings: LiaraAiSettings) {
    setError(null);
    setNotice(null);
    try {
      const saved = await window.mirook.saveAiSettings(nextSettings);
      setAiSettings(saved);
      closeSettings();
      setNotice("Liara settings saved.");
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  function openSettings() {
    setSettingsMounted(true);
    window.requestAnimationFrame(() => setSettingsOpen(true));
  }

  function closeSettings() {
    setSettingsOpen(false);
  }

  function openAiDialog(mode: AiDialogMode) {
    setAiDialogMode(mode);
    setAiMounted(true);
    setAiOpen(false);
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => setAiOpen(true));
    });
  }

  function closeAiDialog() {
    setAiOpen(false);
  }

  async function summarizePageRange(startPage: number, endPage: number) {
    if (!book) return;
    setError(null);
    setNotice(null);
    setIsSummarizing(true);
    try {
      const start = Math.min(startPage, endPage);
      const end = Math.max(startPage, endPage);
      const text = summaryTextForRange(book, start, end);
      const summary = await window.mirook.summarizePages({
        bookId: book.id,
        startPage: start,
        endPage: end,
        text
      });
      setLatestSummary(summary);
      setSummaries((items) => [summary, ...items.filter((item) => item.id !== summary.id)]);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setIsSummarizing(false);
    }
  }

  async function generateTextFromNotes(startPage: number, endPage: number, color: string | null, notesOnly: boolean) {
    if (!book) return;
    setError(null);
    setNotice(null);
    setIsGeneratingNotesText(true);
    try {
      const start = Math.min(startPage, endPage);
      const end = Math.max(startPage, endPage);
      const text = notesTextForRange(annotations, start, end, color, notesOnly);
      const output = await window.mirook.generateTextFromNotes({
        bookId: book.id,
        startPage: start,
        endPage: end,
        text
      });
      setLatestSummary(output);
      setSummaries((items) => [output, ...items.filter((item) => item.id !== output.id)]);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setIsGeneratingNotesText(false);
    }
  }

  async function deleteAiOutput(id: string) {
    setError(null);
    try {
      await window.mirook.deleteAiOutput(id);
      setSummaries((items) => items.filter((item) => item.id !== id));
      setLatestSummary((item) => (item?.id === id ? null : item));
      setPendingDeleteAiOutputId(null);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function handleHeaderDoubleClick(event: ReactMouseEvent<HTMLElement>) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest("button, a, input, select, textarea, [data-window-control]")) return;
    await window.mirook.toggleWindowZoom();
  }

  return (
    <div className="flex h-full w-full flex-col overflow-hidden bg-cream text-ink">
      <header
        onDoubleClick={handleHeaderDoubleClick}
        className="app-drag-region flex h-16 shrink-0 items-center justify-between gap-4 border-b border-line bg-paper/90 py-0 pl-[88px] pr-6"
      >
        <div className="flex min-w-0 flex-1 items-center gap-3">
          <LogoMark />
          <div className="min-w-0">
            <h1 className="truncate text-base font-semibold">{hasBook ? title : "Mirook Reader"}</h1>
            <p className="text-xs text-muted">
              {hasBook ? `${sourceKind.toUpperCase()} source · Page ${pageIndex + 1} of ${pageCount}` : "Open an MRBK file to begin"}
            </p>
          </div>
        </div>

        <div className="app-no-drag flex shrink-0 items-center gap-2" data-window-control>
          <ModeSwitch value={viewMode} onChange={setViewMode} disabled={!hasBook} />
          <button
            type="button"
            onClick={() => setNotesOpen((value) => !value)}
            disabled={!hasBook}
            className={`relative inline-flex h-10 w-10 items-center justify-center rounded-lg border border-line hover:bg-cream disabled:opacity-35 ${
              notesOpen ? "bg-ink text-white hover:bg-black" : "bg-white"
            }`}
            title="Notes and highlights"
          >
            <StickyNote size={18} />
            {annotations.length ? (
              <span
                className={`absolute -right-1 -top-1 min-w-5 rounded-full px-1.5 py-0.5 text-[10px] font-bold leading-none ${
                  notesOpen ? "bg-white text-ink" : "bg-ink text-white"
                }`}
              >
                {annotations.length}
              </span>
            ) : null}
          </button>
          <button
            type="button"
            onClick={openSettings}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-line bg-white hover:bg-cream"
            title="Settings"
          >
            <Settings size={18} />
          </button>
          <div className="relative" data-ai-menu>
            <button
              type="button"
              onClick={() => setAiMenuOpen((value) => !value)}
              disabled={!hasBook}
              className={`inline-flex h-10 w-10 items-center justify-center rounded-lg border border-line hover:bg-cream disabled:opacity-35 ${
                aiMenuOpen ? "bg-ink text-white hover:bg-black" : "bg-white"
              }`}
              title="AI"
            >
              <Sparkles size={18} />
            </button>
            {aiMenuOpen ? (
              <div className="absolute right-0 top-12 z-50 w-48 rounded-xl border border-line bg-white p-1.5 shadow-2xl">
                <button
                  type="button"
                  onClick={() => {
                    openAiDialog("create");
                    setAiMenuOpen(false);
                  }}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm font-semibold hover:bg-cream"
                >
                  <Sparkles size={16} />
                  Create
                </button>
                <button
                  type="button"
                  onClick={() => {
                    openAiDialog("generated");
                    setAiMenuOpen(false);
                  }}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm font-semibold hover:bg-cream"
                >
                  <FileText size={16} />
                  View generated
                </button>
              </div>
            ) : null}
          </div>
          <button
            type="button"
            onClick={openBook}
            disabled={isOpening}
            className="ml-2 inline-flex h-10 min-w-[132px] items-center justify-center gap-2 whitespace-nowrap rounded-lg bg-ink px-4 text-sm font-semibold text-white shadow-sm hover:bg-black disabled:opacity-55"
          >
            {isOpening ? <Loader2 className="animate-spin" size={18} /> : <FolderOpen size={18} />}
            Open MRBK
          </button>
        </div>
      </header>

      {error ? (
        <div className="mx-8 mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>
      ) : null}
      {notice ? (
        <div className="mx-8 mt-4 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">{notice}</div>
      ) : null}

      <main ref={scrollRef} className="min-h-0 flex-1 overflow-hidden px-8 py-7">
        {!book ? (
          <EmptyState isOpening={isOpening} onOpen={openBook} />
        ) : (
          <ReaderLayout
            book={book}
            page={page}
            pageIndex={pageIndex}
            sourceBlocks={sourceBlocks}
            originalFontSize={originalFontSize}
            translationFontSize={translationFontSize}
            viewMode={viewMode}
            annotations={annotations}
            notesColorFilter={notesColorFilter}
            notesOpen={notesOpen}
            notesMounted={notesMounted}
            onOriginalFontSizeChange={setOriginalFontSize}
            onTranslationFontSizeChange={setTranslationFontSize}
            onSelectionContextMenu={handleSelectionContextMenu}
            onNotesColorFilterChange={setNotesColorFilter}
            onDeleteAnnotation={deleteAnnotation}
            onGoToAnnotation={(annotation) => {
              setPageIndex(annotation.page_index);
              setViewMode(annotation.side === "original" ? "original" : "translation");
            }}
          />
        )}
      </main>

      {selection ? (
        <SelectionToolbar
          selection={selection}
          noteDraft={noteDraft}
          selectedColor={selectedHighlightColor}
          onNoteDraftChange={setNoteDraft}
          onSelectedColorChange={setSelectedHighlightColor}
          onHighlight={() => saveSelectedAnnotation(null)}
          onSaveNote={() => saveSelectedAnnotation(noteDraft)}
          onClose={() => {
            setSelection(null);
            setNoteDraft("");
            window.getSelection()?.removeAllRanges();
          }}
        />
      ) : null}

      {settingsMounted ? (
        <SettingsDialog
          open={settingsOpen}
          settings={aiSettings}
          hasBook={hasBook}
          onClose={closeSettings}
          onSave={saveAiSettings}
          onExportData={exportBookData}
        />
      ) : null}

      {aiMounted ? (
        <AiDialog
          mode={aiDialogMode}
          open={aiOpen}
          pageIndex={pageIndex}
          pageCount={pageCount}
          isSummarizing={isSummarizing}
          latestSummary={latestSummary}
          summaries={summaries}
          annotations={annotations}
          isGeneratingNotesText={isGeneratingNotesText}
          onClose={closeAiDialog}
          onSummarize={summarizePageRange}
          onGenerateFromNotes={generateTextFromNotes}
          onDeleteAiOutput={setPendingDeleteAiOutputId}
        />
      ) : null}

      {pendingDeleteAiOutputId ? (
        <ConfirmDialog
          title="Delete generated output?"
          body="This output will be removed from this book's local database."
          confirmLabel="Delete"
          onCancel={() => setPendingDeleteAiOutputId(null)}
          onConfirm={() => deleteAiOutput(pendingDeleteAiOutputId)}
        />
      ) : null}

      <PageNavigator
        hasBook={hasBook}
        pageIndex={pageIndex}
        pageCount={pageCount}
        canGoPrevious={canGoPrevious}
        canGoNext={canGoNext}
        onPrevious={() => setPageIndex((value) => Math.max(0, value - 1))}
        onNext={() => setPageIndex((value) => Math.min(pageCount - 1, value + 1))}
        onGoToPage={(pageNumber) => setPageIndex(clampPageIndex(pageNumber - 1, pageCount))}
      />
    </div>
  );
}

function ReaderLayout({
  book,
  page,
  pageIndex,
  sourceBlocks,
  originalFontSize,
  translationFontSize,
  viewMode,
  annotations,
  notesColorFilter,
  notesOpen,
  notesMounted,
  onOriginalFontSizeChange,
  onTranslationFontSizeChange,
  onSelectionContextMenu,
  onNotesColorFilterChange,
  onDeleteAnnotation,
  onGoToAnnotation
}: {
  book: MirookBookPayload;
  page?: TranslatedTextPage;
  pageIndex: number;
  sourceBlocks?: EpubBlock[];
  originalFontSize: number;
  translationFontSize: number;
  viewMode: ViewMode;
  annotations: ReaderAnnotation[];
  notesColorFilter: string | null;
  notesOpen: boolean;
  notesMounted: boolean;
  onOriginalFontSizeChange: (value: number | ((current: number) => number)) => void;
  onTranslationFontSizeChange: (value: number | ((current: number) => number)) => void;
  onSelectionContextMenu: (side: AnnotationSide, pageIndex: number, event: ReactMouseEvent<HTMLElement>) => void;
  onNotesColorFilterChange: (color: string | null) => void;
  onDeleteAnnotation: (id: string) => void;
  onGoToAnnotation: (annotation: ReaderAnnotation) => void;
}) {
  const translatedBlocks = translatedDisplayBlocks(sourceBlocks, page);
  const originalBlocks = sourceDisplayBlocks(sourceBlocks, page);
  const sourceText = sourcePlainText(sourceBlocks, page?.sourceText ?? "");
  const showOriginal = viewMode === "split" || viewMode === "original";
  const showTranslation = viewMode === "split" || viewMode === "translation";
  const pageAnnotations = annotations.filter((annotation) => annotation.page_index === pageIndex);
  const isSingleColumn = viewMode !== "split";

  return (
    <div className={`mx-auto flex h-full min-h-0 gap-5 ${isSingleColumn ? "max-w-none justify-center" : "max-w-[1720px]"}`}>
      <div
        className={
          viewMode === "split"
            ? "grid h-full min-h-0 min-w-0 flex-1 grid-cols-2 gap-5 transition-[width,flex-basis] duration-200 ease-out"
            : "grid h-full min-h-0 w-full max-w-[850px] shrink-0 grid-cols-1 transition-[width,flex-basis] duration-200 ease-out"
        }
      >
        {showOriginal ? (
          <Paper
            key={`original-${pageIndex}`}
            title="Original"
            pageIndex={pageIndex}
            side="original"
            fontSize={originalFontSize}
            onFontSizeChange={onOriginalFontSizeChange}
            onSelectionContextMenu={onSelectionContextMenu}
            pageShape={isSingleColumn}
          >
            {book.manifest.sourceKind === "pdf" && book.sourcePdf ? (
              <iframe src={book.sourcePdf} className="h-full min-h-[420px] w-full rounded-lg border border-line bg-white" title="Original PDF" />
            ) : originalBlocks.length ? (
              <BlockFlow blocks={originalBlocks} fontSize={originalFontSize} direction="ltr" side="original" pageIndex={pageIndex} annotations={pageAnnotations} />
            ) : page?.isBlank || !sourceText ? (
              <div className="h-full min-h-[420px]" />
            ) : (
              <TextFlow text={sourceText} fontSize={originalFontSize} direction="ltr" side="original" pageIndex={pageIndex} annotations={pageAnnotations} />
            )}
          </Paper>
        ) : null}

        {showTranslation ? (
          <Paper
            key={`translation-${pageIndex}`}
            title="Translation"
            pageIndex={pageIndex}
            side="translation"
            fontSize={translationFontSize}
            onFontSizeChange={onTranslationFontSizeChange}
            onSelectionContextMenu={onSelectionContextMenu}
            pageShape={isSingleColumn}
          >
            {page?.isBlank ? (
              <div className="h-full min-h-[420px]" />
            ) : translatedBlocks.length ? (
              <DisplayFlow blocks={translatedBlocks} fontSize={translationFontSize} pageIndex={pageIndex} annotations={pageAnnotations} />
            ) : (
              <div className="flex h-full min-h-[420px] items-center justify-center text-center text-muted">No translation for this page yet.</div>
            )}
          </Paper>
        ) : null}
      </div>

      <div
        className={`min-h-0 shrink-0 overflow-hidden transition-[width] duration-300 ease-out ${
          notesOpen ? "w-80" : "w-0"
        }`}
      >
        {notesMounted ? (
          <NotesPanel
            open={notesOpen}
            annotations={annotations}
            currentPageIndex={pageIndex}
            colorFilter={notesColorFilter}
            onColorFilterChange={onNotesColorFilterChange}
            onDelete={onDeleteAnnotation}
            onGoTo={onGoToAnnotation}
          />
        ) : null}
      </div>
    </div>
  );
}

function PageNavigator({
  hasBook,
  pageIndex,
  pageCount,
  canGoPrevious,
  canGoNext,
  onPrevious,
  onNext,
  onGoToPage
}: {
  hasBook: boolean;
  pageIndex: number;
  pageCount: number;
  canGoPrevious: boolean;
  canGoNext: boolean;
  onPrevious: () => void;
  onNext: () => void;
  onGoToPage: (pageNumber: number) => void;
}) {
  return (
    <footer className="flex h-20 shrink-0 items-center justify-center border-t border-line bg-paper/90 px-8">
      <div className="flex w-full max-w-5xl items-center justify-between gap-4 rounded-2xl border border-line bg-white/80 p-2 shadow-sm">
        <button
          type="button"
          disabled={!canGoPrevious}
          onClick={onPrevious}
          className="inline-flex h-11 items-center gap-2 rounded-xl px-5 text-sm font-medium hover:bg-cream disabled:opacity-35"
        >
          <ChevronLeft size={20} />
          Previous
        </button>

        <div className="mx-6 min-w-[280px] flex-1">
          <div className="text-center text-sm font-semibold text-muted">{hasBook ? `Page ${pageIndex + 1} / ${pageCount}` : "No book open"}</div>
          <input
            type="range"
            min={1}
            max={Math.max(pageCount, 1)}
            value={hasBook ? pageIndex + 1 : 1}
            disabled={!hasBook}
            onChange={(event) => onGoToPage(Number(event.target.value))}
            className="page-scrubber mt-1 w-full disabled:opacity-30"
            aria-label="Page scrubber"
          />
        </div>

        <button
          type="button"
          disabled={!canGoNext}
          onClick={onNext}
          className="inline-flex h-11 items-center gap-2 rounded-xl px-5 text-sm font-medium hover:bg-cream disabled:opacity-35"
        >
          Next
          <ChevronRight size={20} />
        </button>
        {hasBook ? <ReadingProgress currentPage={pageIndex + 1} pageCount={pageCount} /> : null}
      </div>
    </footer>
  );
}

function ReadingProgress({ currentPage, pageCount }: { currentPage: number; pageCount: number }) {
  const percent = pageCount ? Math.round((currentPage / pageCount) * 100) : 0;
  const clampedPercent = Math.max(0, Math.min(100, percent));
  return (
    <div
      className="pointer-events-none flex h-14 w-14 shrink-0 items-center justify-center rounded-full p-[3px] shadow-soft"
      style={{
        background: `conic-gradient(#171717 ${clampedPercent * 3.6}deg, #e6ded2 0deg)`
      }}
      aria-label={`Reading progress ${clampedPercent}%`}
    >
      <div className="flex h-full w-full flex-col items-center justify-center rounded-full border border-white/70 bg-paper/95 text-ink backdrop-blur">
        <span className="text-xs font-bold leading-none">{clampedPercent}%</span>
        <span className="mt-1 text-[9px] font-semibold leading-none text-muted">{currentPage}/{pageCount}</span>
      </div>
    </div>
  );
}

function Paper({
  title,
  pageIndex,
  side,
  fontSize,
  onFontSizeChange,
  onSelectionContextMenu,
  pageShape = false,
  children
}: {
  title: string;
  pageIndex: number;
  side: AnnotationSide;
  fontSize: number;
  onFontSizeChange: (value: number | ((current: number) => number)) => void;
  onSelectionContextMenu: (side: AnnotationSide, pageIndex: number, event: ReactMouseEvent<HTMLElement>) => void;
  pageShape?: boolean;
  children: ReactNode;
}) {
  return (
    <section
      className={`flex min-h-0 min-w-0 flex-col overflow-hidden rounded-2xl border border-line bg-white shadow-soft ${
        pageShape ? "mx-auto h-full w-full" : "h-full"
      }`}
    >
      <div className="flex shrink-0 items-center justify-between gap-3 border-b border-line bg-paper px-6 py-4">
        <div className="min-w-0">
          <h2 className="truncate text-sm font-semibold">
            {title} <span className="text-muted">| Page {pageIndex + 1}</span>
          </h2>
        </div>
        <FontSizeControl value={fontSize} onChange={onFontSizeChange} label={`${title} text size`} />
      </div>
      <div
        data-reader-scroll-pane
        onContextMenu={(event) => onSelectionContextMenu(side, pageIndex, event)}
        className={`paper-scroll min-h-0 flex-1 overflow-auto bg-white ${
          side === "original" ? "px-14 py-14" : "px-12 py-10"
        }`}
      >
        {children}
      </div>
    </section>
  );
}

function FontSizeControl({
  value,
  onChange,
  label
}: {
  value: number;
  onChange: (value: number | ((current: number) => number)) => void;
  label: string;
}) {
  return (
    <div className="app-no-drag inline-flex shrink-0 items-center rounded-lg border border-line bg-white p-1" aria-label={label}>
      <button
        type="button"
        onClick={() => onChange((current) => Math.max(14, current - 1))}
        className="inline-flex h-7 w-7 items-center justify-center rounded-md text-muted hover:bg-cream hover:text-ink"
        title="Smaller text"
      >
        <Minus size={15} />
      </button>
      <span className="w-8 text-center text-xs font-semibold text-muted">{value}</span>
      <button
        type="button"
        onClick={() => onChange((current) => Math.min(36, current + 1))}
        className="inline-flex h-7 w-7 items-center justify-center rounded-md text-muted hover:bg-cream hover:text-ink"
        title="Larger text"
      >
        <Plus size={15} />
      </button>
    </div>
  );
}

function DisplayFlow({
  blocks,
  fontSize,
  pageIndex,
  annotations
}: {
  blocks: DisplayBlock[];
  fontSize: number;
  pageIndex: number;
  annotations: ReaderAnnotation[];
}) {
  return (
    <div className="font-vazir leading-[2.05]" dir="rtl" style={{ fontSize }}>
      {blocks.map((block, index) => {
        if (block.type === "image") {
          return <BookImage key={index} src={block.src} alt={block.altText ?? ""} />;
        }
        if (block.type === "link") {
          return (
            <p key={index} className="mb-5 text-right">
              <a className="text-blue-700 underline" href={block.href}>
                {block.title}
              </a>
            </p>
          );
        }
        const blockId = textBlockId("translation", pageIndex, index);
        return <TranslationTextBlock key={index} text={block.text} blockId={blockId} annotations={annotationsForBlock(annotations, blockId)} />;
      })}
    </div>
  );
}

function TranslationTextBlock({ text, blockId, annotations }: { text: string; blockId: string; annotations: ReaderAnnotation[] }) {
  const lines = text
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split("\n");
  let cursor = 0;

  return (
    <div data-annotation-block-id={blockId} className="mb-5 text-right">
      {lines.map((line, index) => {
        const lineStart = cursor;
        cursor += line.length + (index < lines.length - 1 ? 1 : 0);
        if (!line.trim()) return <br key={index} />;
        return (
          <div key={`${index}-${line}`} className={`whitespace-pre-wrap ${isTranslationHeadingLine(line) ? "font-bold" : ""}`}>
            <MarkedText text={line} annotations={annotationsForTextRange(annotations, lineStart, lineStart + line.length)} />
          </div>
        );
      })}
    </div>
  );
}

function BlockFlow({
  blocks,
  fontSize,
  direction,
  side,
  pageIndex,
  annotations
}: {
  blocks: (EpubBlock | DisplayBlock)[];
  fontSize: number;
  direction: "rtl" | "ltr";
  side: AnnotationSide;
  pageIndex: number;
  annotations: ReaderAnnotation[];
}) {
  if (direction === "ltr") {
    return <OriginalPdfFlow blocks={blocks} fontSize={fontSize} side={side} pageIndex={pageIndex} annotations={annotations} />;
  }

  const flowStyle: CSSProperties = {
    fontSize,
    lineHeight: 1.75
  };

  return (
    <div className="font-vazir" dir={direction} style={flowStyle}>
      {blocks.map((block, index) => (
        <Block
          key={index}
          block={block}
          fontSize={fontSize}
          direction={direction}
          blockId={textBlockId(side, pageIndex, index)}
          annotations={annotations}
        />
      ))}
    </div>
  );
}

function OriginalPdfFlow({
  blocks,
  fontSize,
  side,
  pageIndex,
  annotations
}: {
  blocks: (EpubBlock | DisplayBlock)[];
  fontSize: number;
  side: AnnotationSide;
  pageIndex: number;
  annotations: ReaderAnnotation[];
}) {
  return (
    <div className="original-pdf-page mx-auto w-full max-w-[760px]" dir="ltr" style={{ fontSize }}>
      {blocks.map((block, index) => {
        if (block.type === "image") return <BookImage key={index} src={block.src} alt={block.altText ?? ""} compact />;
        const blockId = textBlockId(side, pageIndex, index);
        const blockAnnotations = annotationsForBlock(annotations, blockId);
        if (block.type === "link") {
          return (
            <OriginalPdfTextBlock
              key={index}
              text={block.title}
              blockId={blockId}
              annotations={blockAnnotations}
              linkHref={block.href}
            />
          );
        }
        return <OriginalPdfTextBlock key={index} text={block.text} blockId={blockId} annotations={blockAnnotations} />;
      })}
    </div>
  );
}

function OriginalPdfTextBlock({
  text,
  blockId,
  annotations,
  linkHref
}: {
  text: string;
  blockId: string;
  annotations: ReaderAnnotation[];
  linkHref?: string;
}) {
  const lines = originalPdfLines(text);
  let cursor = 0;

  return (
    <div data-annotation-block-id={blockId} className="original-pdf-block">
      {lines.map((line, index) => {
        const lineStart = cursor;
        cursor += line.raw.length + (index < lines.length - 1 ? 1 : 0);
        const lineAnnotations = annotationsForTextRange(annotations, lineStart, lineStart + line.raw.length);
        const content = <MarkedText text={line.raw} annotations={lineAnnotations} />;
        return (
          <div
            key={`${index}-${line.raw}`}
            className={`original-pdf-line ${line.indented ? "original-pdf-line-indent" : ""} ${
              line.heading ? "original-pdf-heading" : ""
            }`}
          >
            {linkHref ? (
              <a className="text-blue-700 underline" href={linkHref}>
                {content}
              </a>
            ) : (
              content
            )}
          </div>
        );
      })}
    </div>
  );
}

function Block({
  block,
  fontSize,
  direction,
  blockId,
  annotations
}: {
  block: EpubBlock | DisplayBlock;
  fontSize: number;
  direction: "rtl" | "ltr";
  blockId: string;
  annotations: ReaderAnnotation[];
}) {
  if (block.type === "image") return <BookImage src={block.src} alt={block.altText ?? ""} compact />;
  const textStyle: CSSProperties = {
    fontSize,
    lineHeight: direction === "rtl" ? 2.05 : ORIGINAL_READER_LINE_HEIGHT
  };
  const className =
    direction === "rtl"
      ? "font-vazir mb-5 whitespace-pre-wrap text-right"
      : "mb-[18px] whitespace-pre-wrap";

  if (block.type === "link") {
    return (
      <p className={className} dir={direction} style={textStyle}>
        <a className="text-blue-700 underline" href={block.href}>
          {block.title}
        </a>
      </p>
    );
  }

  return (
    <p data-annotation-block-id={blockId} className={className} dir={direction} style={textStyle}>
      <MarkedText text={block.text} annotations={annotationsForBlock(annotations, blockId)} />
    </p>
  );
}

function TextFlow({
  text,
  fontSize,
  direction,
  side,
  pageIndex,
  annotations
}: {
  text: string;
  fontSize: number;
  direction: "rtl" | "ltr";
  side: AnnotationSide;
  pageIndex: number;
  annotations: ReaderAnnotation[];
}) {
  if (direction === "ltr") {
    return (
      <OriginalPdfFlow
        blocks={text ? [{ type: "text", text }] : []}
        fontSize={fontSize}
        side={side}
        pageIndex={pageIndex}
        annotations={annotations}
      />
    );
  }

  const textStyle: CSSProperties = {
    fontSize,
    lineHeight: 1.8
  };

  return (
    <div className="font-vazir" dir={direction} style={textStyle}>
      {text.split(/\n{2,}/).map((paragraph, index) => {
        const blockId = textBlockId(side, pageIndex, index);
        return (
          <p key={index} data-annotation-block-id={blockId} className="mb-[18px] whitespace-pre-wrap">
            <MarkedText text={paragraph} annotations={annotationsForBlock(annotations, blockId)} />
          </p>
        );
      })}
    </div>
  );
}

function BookImage({ src, alt, compact = false }: { src: string; alt: string; compact?: boolean }) {
  return (
    <figure className={`${compact ? "my-0" : "my-8"} flex w-full flex-col items-center`}>
      <img src={src} alt={alt} className="max-h-[640px] max-w-full object-contain" />
      {alt ? <figcaption className="mt-2 text-center text-sm text-muted">{alt}</figcaption> : null}
    </figure>
  );
}

function MarkedText({ text, annotations }: { text: string; annotations: ReaderAnnotation[] }) {
  if (!annotations.length) return <>{text}</>;
  const ranges = annotations
    .map((annotation) => ({
      ...annotation,
      start: Math.max(0, Math.min(text.length, Number(annotation.start_offset))),
      end: Math.max(0, Math.min(text.length, Number(annotation.end_offset)))
    }))
    .filter((annotation) => annotation.end > annotation.start)
    .sort((a, b) => a.start - b.start || a.end - b.end);

  const nodes: ReactNode[] = [];
  let cursor = 0;
  ranges.forEach((annotation) => {
    if (annotation.start < cursor) return;
    if (annotation.start > cursor) nodes.push(text.slice(cursor, annotation.start));
    nodes.push(
      <HighlightMark key={annotation.id} annotation={annotation}>
        {text.slice(annotation.start, annotation.end)}
      </HighlightMark>
    );
    cursor = annotation.end;
  });
  if (cursor < text.length) nodes.push(text.slice(cursor));
  return <>{nodes}</>;
}

function HighlightMark({ annotation, children }: { annotation: ReaderAnnotation; children: ReactNode }) {
  const hasNote = Boolean(annotation.note?.trim());
  const [popoverPosition, setPopoverPosition] = useState<NotePopoverPosition | null>(null);

  function showNotePopover(event: ReactMouseEvent<HTMLElement>) {
    if (!hasNote) return;
    setPopoverPosition(notePopoverPosition({ x: event.clientX, y: event.clientY }));
  }

  function hideNotePopover() {
    setPopoverPosition(null);
  }

  return (
    <span className="relative inline" onMouseEnter={showNotePopover} onMouseMove={showNotePopover} onMouseLeave={hideNotePopover}>
      <mark
        className="rounded px-0.5"
        style={{ backgroundColor: annotation.color || "#fde68a" }}
      >
        {children}
      </mark>
      {hasNote && popoverPosition ? (
        <span
          className="pointer-events-none fixed z-50 whitespace-normal rounded-xl border border-stone-300 bg-paper px-4 py-3 text-ink shadow-2xl"
          dir="rtl"
          style={{ left: popoverPosition.left, top: popoverPosition.top, width: popoverPosition.width }}
        >
          <span
            className={`absolute h-4 w-4 rotate-45 rounded-[3px] border-stone-300 bg-paper ${
              popoverPosition.placement === "below" ? "top-0 -translate-y-1/2 border-l border-t" : "bottom-0 translate-y-1/2 border-b border-r"
            }`}
            style={{ left: popoverPosition.arrowLeft }}
          />
          <span className="relative z-10 block text-center text-[11px] font-bold text-muted">یادداشت</span>
          <span className="relative z-10 mt-2 block max-h-52 overflow-auto text-right font-vazir text-[15px] font-semibold leading-7 text-neutral-700">
            {annotation.note}
          </span>
        </span>
      ) : null}
    </span>
  );
}

function notePopoverPosition(anchor: NotePopoverAnchor): NotePopoverPosition {
  const margin = 16;
  const gap = 14;
  const width = Math.min(320, window.innerWidth - margin * 2);
  const estimatedHeight = 160;
  const targetX = anchor.x;
  const left = Math.max(margin, Math.min(window.innerWidth - width - margin, targetX - width / 2));
  const fitsBelow = anchor.y + gap + estimatedHeight <= window.innerHeight - margin;
  const placement: NotePopoverPosition["placement"] = fitsBelow ? "below" : "above";
  const top = placement === "below"
    ? Math.max(margin, Math.min(window.innerHeight - estimatedHeight - margin, anchor.y + gap))
    : Math.max(margin, anchor.y - gap - estimatedHeight);
  const arrowLeft = Math.max(24, Math.min(width - 24, targetX - left));
  return { left, top, width, arrowLeft, placement };
}

function SelectionToolbar({
  selection,
  noteDraft,
  selectedColor,
  onNoteDraftChange,
  onSelectedColorChange,
  onHighlight,
  onSaveNote,
  onClose
}: {
  selection: SelectionState;
  noteDraft: string;
  selectedColor: string;
  onNoteDraftChange: (value: string) => void;
  onSelectedColorChange: (value: string) => void;
  onHighlight: () => void;
  onSaveNote: () => void;
  onClose: () => void;
}) {
  return (
    <div
      data-selection-toolbar
      className="fixed z-50 w-80 rounded-xl border border-line bg-white p-3 shadow-2xl"
      style={{ left: selection.x, top: selection.y }}
    >
      <div className="mb-2 flex items-start justify-between gap-3">
        <div className="min-w-0 text-xs text-muted">
          <div className="font-semibold text-ink">{selection.side === "original" ? "Original" : "Translation"} · Page {selection.pageIndex + 1}</div>
          <div className="mt-1 line-clamp-2">{selection.selectedText}</div>
        </div>
        <button type="button" onClick={onClose} className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-md hover:bg-cream">
          <X size={15} />
        </button>
      </div>
      <textarea
        value={noteDraft}
        onChange={(event) => onNoteDraftChange(event.target.value)}
        placeholder="Add a comment..."
        className="h-20 w-full resize-none rounded-lg border border-line bg-paper px-3 py-2 text-sm outline-none focus:border-amber-400"
      />
      <div className="mt-3 flex items-center gap-2">
        {HIGHLIGHT_COLORS.map((color) => (
          <button
            key={color.value}
            type="button"
            onClick={() => onSelectedColorChange(color.value)}
            className={`h-7 w-7 rounded-full border ${
              selectedColor === color.value ? "border-ink ring-2 ring-ink/20" : "border-line"
            }`}
            style={{ backgroundColor: color.value }}
            title={color.label}
          />
        ))}
      </div>
      <div className="mt-3 flex items-center justify-between gap-2">
        <button
          type="button"
          onClick={onHighlight}
          className="inline-flex h-9 items-center gap-2 rounded-lg px-3 text-sm font-semibold text-ink hover:brightness-95"
          style={{ backgroundColor: selectedColor }}
        >
          <Highlighter size={16} />
          Highlight
        </button>
        <button
          type="button"
          onClick={onSaveNote}
          className="inline-flex h-9 items-center gap-2 rounded-lg bg-ink px-3 text-sm font-semibold text-white hover:bg-black"
        >
          {noteDraft.trim() ? <MessageSquare size={16} /> : <Highlighter size={16} />}
          {noteDraft.trim() ? "Save note" : "Save highlight"}
        </button>
      </div>
    </div>
  );
}

function SettingsDialog({
  open,
  settings,
  hasBook,
  onClose,
  onSave,
  onExportData
}: {
  open: boolean;
  settings: LiaraAiSettings;
  hasBook: boolean;
  onClose: () => void;
  onSave: (settings: LiaraAiSettings) => void;
  onExportData: () => void;
}) {
  const [draft, setDraft] = useState<LiaraAiSettings>(settings);
  const [activeTab, setActiveTab] = useState<SettingsTab>("ai");

  useEffect(() => {
    setDraft(settings);
  }, [settings]);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    onSave(draft);
  }

  return (
    <div
      className={`app-no-drag fixed bottom-0 left-0 right-0 top-16 z-50 bg-black/25 transition-opacity duration-200 ${open ? "opacity-100" : "opacity-0"}`}
      onMouseDown={onClose}
    >
      <form
        onSubmit={handleSubmit}
        onMouseDown={(event) => event.stopPropagation()}
        className={`h-full w-[420px] max-w-[calc(100vw-24px)] border-r border-line bg-white p-5 shadow-2xl transition-transform duration-200 ease-out ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <div className="mb-5 flex items-start justify-between gap-4">
          <div>
            <h2 className="text-base font-semibold">Settings</h2>
            <p className="mt-1 text-sm leading-6 text-muted">Configure AI and local reader data.</p>
          </div>
          <button type="button" onClick={onClose} className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg hover:bg-cream">
            <X size={18} />
          </button>
        </div>

        <div className="mb-5 grid grid-cols-2 rounded-xl bg-cream p-1">
          <button
            type="button"
            onClick={() => setActiveTab("ai")}
            className={`h-9 rounded-lg px-4 text-sm font-semibold transition ${activeTab === "ai" ? "bg-white text-ink shadow-sm" : "text-muted hover:text-ink"}`}
          >
            AI
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("data")}
            className={`h-9 rounded-lg px-4 text-sm font-semibold transition ${activeTab === "data" ? "bg-white text-ink shadow-sm" : "text-muted hover:text-ink"}`}
          >
            Data
          </button>
        </div>

        {activeTab === "ai" ? (
          <>
            <label className="mb-4 block">
              <span className="mb-2 block text-sm font-semibold text-ink">URL</span>
              <input
                value={draft.url}
                onChange={(event) => setDraft((value) => ({ ...value, url: event.target.value }))}
                placeholder="https://..."
                className="h-11 w-full rounded-xl border border-line bg-paper px-3 text-sm outline-none focus:border-amber-400"
              />
            </label>

            <label className="block">
              <span className="mb-2 block text-sm font-semibold text-ink">API Key</span>
              <input
                value={draft.apiKey}
                onChange={(event) => setDraft((value) => ({ ...value, apiKey: event.target.value }))}
                type="password"
                placeholder="Liara API key"
                className="h-11 w-full rounded-xl border border-line bg-paper px-3 text-sm outline-none focus:border-amber-400"
              />
            </label>

            <label className="mt-4 block">
              <span className="mb-2 block text-sm font-semibold text-ink">Model</span>
              <select
                value={draft.model || AI_MODELS[0].value}
                onChange={(event) => setDraft((value) => ({ ...value, model: event.target.value }))}
                className="h-11 w-full rounded-xl border border-line bg-paper px-3 text-sm outline-none focus:border-amber-400"
              >
                {AI_MODELS.map((model) => (
                  <option key={model.value} value={model.value}>
                    {model.label}
                  </option>
                ))}
              </select>
            </label>

            <div className="mt-5 flex items-center justify-end gap-2">
              <button type="button" onClick={onClose} className="h-10 rounded-xl px-4 text-sm font-semibold text-muted hover:bg-cream">
                Cancel
              </button>
              <button type="submit" className="inline-flex h-10 items-center gap-2 rounded-xl bg-ink px-4 text-sm font-semibold text-white hover:bg-black">
                <Save size={16} />
                Save
              </button>
            </div>
          </>
        ) : (
          <div>
            <section className="rounded-xl border border-line bg-paper p-4">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-white text-ink">
                  <Download size={18} />
                </div>
                <div className="min-w-0 flex-1">
                  <h3 className="text-sm font-semibold text-ink">Export reader data</h3>
                  <p className="mt-1 text-sm leading-6 text-muted">
                    Export this book's reading position, highlights, notes, and generated AI outputs as JSON.
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={onExportData}
                disabled={!hasBook}
                className="mt-4 inline-flex h-10 w-full items-center justify-center gap-2 rounded-xl bg-ink px-4 text-sm font-semibold text-white hover:bg-black disabled:opacity-40"
              >
                <Download size={16} />
                Export data
              </button>
            </section>
          </div>
        )}
      </form>
    </div>
  );
}

function AiDialog({
  mode,
  open,
  pageIndex,
  pageCount,
  isSummarizing,
  latestSummary,
  summaries,
  annotations,
  isGeneratingNotesText,
  onClose,
  onSummarize,
  onGenerateFromNotes,
  onDeleteAiOutput
}: {
  mode: AiDialogMode;
  open: boolean;
  pageIndex: number;
  pageCount: number;
  isSummarizing: boolean;
  latestSummary: ReaderSummary | null;
  summaries: ReaderSummary[];
  annotations: ReaderAnnotation[];
  isGeneratingNotesText: boolean;
  onClose: () => void;
  onSummarize: (startPage: number, endPage: number) => void;
  onGenerateFromNotes: (startPage: number, endPage: number, color: string | null, notesOnly: boolean) => void;
  onDeleteAiOutput: (id: string) => void;
}) {
  const [startPage, setStartPage] = useState(pageIndex + 1);
  const [endPage, setEndPage] = useState(Math.min(pageCount || 1, pageIndex + 1));
  const [notesStartPage, setNotesStartPage] = useState(pageIndex + 1);
  const [notesEndPage, setNotesEndPage] = useState(Math.min(pageCount || 1, pageIndex + 1));
  const [notesColorFilter, setNotesColorFilter] = useState<string | null>(null);
  const [notesOnly, setNotesOnly] = useState(false);
  const [activeTab, setActiveTab] = useState<AiTab>("new");
  const [selectedSummaryId, setSelectedSummaryId] = useState<string | null>(null);
  const selectedSummary = summaries.find((summary) => summary.id === selectedSummaryId) ?? summaries[0] ?? null;
  const pageSummaries = summaries.filter((summary) => outputType(summary) === "summary");
  const noteOutputs = summaries.filter((summary) => outputType(summary) === "notes");
  const matchingNotesCount = notesForRange(annotations, notesStartPage, notesEndPage, notesColorFilter, notesOnly).length;

  useEffect(() => {
    setStartPage(pageIndex + 1);
    setEndPage(Math.min(pageCount || 1, pageIndex + 1));
    setNotesStartPage(pageIndex + 1);
    setNotesEndPage(Math.min(pageCount || 1, pageIndex + 1));
  }, [pageIndex, pageCount]);

  useEffect(() => {
    if (latestSummary) {
      setActiveTab(latestSummary.output_type === "notes" ? "notes" : "new");
      setSelectedSummaryId(latestSummary.id);
    }
  }, [latestSummary]);

  useEffect(() => {
    if (mode === "create") setActiveTab("new");
  }, [mode]);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (activeTab === "notes") {
      onGenerateFromNotes(
        clampPageNumber(notesStartPage, pageCount),
        clampPageNumber(notesEndPage, pageCount),
        notesColorFilter,
        notesOnly
      );
      return;
    }
    onSummarize(clampPageNumber(startPage, pageCount), clampPageNumber(endPage, pageCount));
  }

  return (
    <div
      data-open={open}
      className={`ai-modal-backdrop app-no-drag fixed bottom-0 left-0 right-0 top-16 z-50 flex items-center justify-center bg-black/25 px-5 py-5 transition-opacity duration-200 ${
        open ? "opacity-100" : "opacity-0"
      }`}
      onMouseDown={onClose}
    >
      <form
        onSubmit={handleSubmit}
        onMouseDown={(event) => event.stopPropagation()}
        data-open={open}
        className={`ai-modal-panel flex max-h-full w-full flex-col overflow-hidden rounded-2xl border border-line bg-white shadow-2xl transition duration-200 ease-out ${
          mode === "generated" ? "max-w-[75vw]" : "max-w-[760px]"
        } ${open ? "translate-y-0 scale-100 opacity-100" : "translate-y-3 scale-[0.98] opacity-0"}`}
      >
        <div className="flex items-start justify-between gap-4 border-b border-line bg-paper px-5 py-4">
          <div>
            <h2 className="flex items-center gap-2 text-base font-semibold">
              <Sparkles size={18} />
              {mode === "create" ? "AI Create" : "Generated"}
            </h2>
            <p className="mt-1 text-sm leading-6 text-muted">
              {mode === "create" ? "Generate Persian summaries or texts from notes." : "Review saved AI outputs for this book."}
            </p>
          </div>
          <button type="button" onClick={onClose} className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg hover:bg-cream">
            <X size={18} />
          </button>
        </div>

        {mode === "create" ? (
          <div className="border-b border-line bg-white px-5 py-3">
            <div className="grid grid-cols-2 rounded-xl bg-cream p-1">
          <button
            type="button"
            onClick={() => setActiveTab("new")}
            className={`h-9 rounded-lg px-4 text-sm font-semibold transition ${activeTab === "new" ? "bg-white text-ink shadow-sm" : "text-muted hover:text-ink"}`}
          >
            New summary
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("notes")}
            className={`h-9 rounded-lg px-4 text-sm font-semibold transition ${activeTab === "notes" ? "bg-white text-ink shadow-sm" : "text-muted hover:text-ink"}`}
          >
            From notes
          </button>
            </div>
          </div>
        ) : null}

        {mode === "generated" ? (
          <GeneratedOutputsView
            summaries={summaries}
            selectedSummary={selectedSummary}
            pageSummaries={pageSummaries}
            noteOutputs={noteOutputs}
            onSelect={(summary) => setSelectedSummaryId(summary.id)}
            onDelete={onDeleteAiOutput}
          />
        ) : activeTab === "new" ? (
          <div className="flex min-h-0 flex-1 flex-col p-5">
            <div className="grid grid-cols-[1fr_1fr_auto] items-end gap-3">
              <label className="block">
                <span className="mb-2 block text-sm font-semibold text-ink">Start page</span>
                <input
                  value={startPage}
                  onChange={(event) => setStartPage(Number(event.target.value))}
                  type="number"
                  min={1}
                  max={Math.max(pageCount, 1)}
                  className="h-11 w-full rounded-xl border border-line bg-paper px-3 text-sm outline-none focus:border-amber-400"
                />
              </label>
              <label className="block">
                <span className="mb-2 block text-sm font-semibold text-ink">End page</span>
                <input
                  value={endPage}
                  onChange={(event) => setEndPage(Number(event.target.value))}
                  type="number"
                  min={1}
                  max={Math.max(pageCount, 1)}
                  className="h-11 w-full rounded-xl border border-line bg-paper px-3 text-sm outline-none focus:border-amber-400"
                />
              </label>
              <button
                type="submit"
                disabled={isSummarizing}
                className="inline-flex h-11 items-center gap-2 rounded-xl bg-ink px-5 text-sm font-semibold text-white hover:bg-black disabled:opacity-55"
              >
                {isSummarizing ? <Loader2 className="animate-spin" size={16} /> : <Sparkles size={16} />}
                Summarize
              </button>
            </div>

            <div className="mt-3 rounded-xl border border-line bg-paper px-4 py-3 text-xs font-medium leading-5 text-muted">
              After generation, the summary is saved automatically in this book's local database.
            </div>

            <div className="paper-scroll mt-5 min-h-0 flex-1 overflow-auto rounded-xl border border-line bg-paper p-4">
              {latestSummary ? (
                <SummaryArticle summary={latestSummary} />
              ) : (
                <div className="flex min-h-32 items-center justify-center text-center text-sm leading-6 text-muted">
                  Choose a range and summarize it.
                </div>
              )}
            </div>
          </div>
        ) : (
          <div className="flex min-h-0 flex-1 flex-col p-5">
            <div className="grid grid-cols-[1fr_1fr] gap-3">
              <label className="block">
                <span className="mb-2 block text-sm font-semibold text-ink">Start page</span>
                <input
                  value={notesStartPage}
                  onChange={(event) => setNotesStartPage(Number(event.target.value))}
                  type="number"
                  min={1}
                  max={Math.max(pageCount, 1)}
                  className="h-11 w-full rounded-xl border border-line bg-paper px-3 text-sm outline-none focus:border-amber-400"
                />
              </label>
              <label className="block">
                <span className="mb-2 block text-sm font-semibold text-ink">End page</span>
                <input
                  value={notesEndPage}
                  onChange={(event) => setNotesEndPage(Number(event.target.value))}
                  type="number"
                  min={1}
                  max={Math.max(pageCount, 1)}
                  className="h-11 w-full rounded-xl border border-line bg-paper px-3 text-sm outline-none focus:border-amber-400"
                />
              </label>
            </div>

            <div className="mt-4 flex flex-wrap items-center gap-2">
              <button
                type="button"
                onClick={() => setNotesColorFilter(null)}
                className={`h-8 rounded-full border px-3 text-xs font-semibold ${
                  notesColorFilter === null ? "border-ink bg-ink text-white" : "border-line bg-white text-muted hover:bg-cream"
                }`}
              >
                All colors
              </button>
              {HIGHLIGHT_COLORS.map((color) => (
                <button
                  key={color.value}
                  type="button"
                  onClick={() => setNotesColorFilter(color.value)}
                  className={`h-8 w-8 rounded-full border ${
                    notesColorFilter === color.value ? "border-ink ring-2 ring-ink/20" : "border-line hover:ring-2 hover:ring-ink/10"
                  }`}
                  style={{ backgroundColor: color.value }}
                  title={color.label}
                />
              ))}
              <label className="ml-auto inline-flex h-8 items-center gap-2 rounded-full border border-line bg-white px-3 text-xs font-semibold text-muted">
                <input
                  type="checkbox"
                  checked={notesOnly}
                  onChange={(event) => setNotesOnly(event.target.checked)}
                  className="h-4 w-4 accent-neutral-900"
                />
                Only notes
              </label>
            </div>

            <div className="mt-4 rounded-xl border border-line bg-paper px-4 py-3 text-sm leading-6 text-muted">
              {matchingNotesCount} matching {notesOnly ? "notes" : "highlights and notes"} will be used. The generated text is saved automatically.
            </div>

            <div className="mt-5 flex items-center justify-end">
              <button
                type="submit"
                disabled={isGeneratingNotesText || !matchingNotesCount}
                className="inline-flex h-10 items-center gap-2 rounded-xl bg-ink px-4 text-sm font-semibold text-white hover:bg-black disabled:opacity-55"
              >
                {isGeneratingNotesText ? <Loader2 className="animate-spin" size={16} /> : <Sparkles size={16} />}
                Generate text
              </button>
            </div>

            <div className="paper-scroll mt-5 min-h-0 flex-1 overflow-auto rounded-xl border border-line bg-paper p-4">
              {latestSummary?.output_type === "notes" ? (
                <SummaryArticle summary={latestSummary} />
              ) : (
                <div className="flex min-h-32 items-center justify-center text-center text-sm leading-6 text-muted">
                  Pick note filters and generate a text from your reading marks.
                </div>
              )}
            </div>
          </div>
        )}
      </form>
    </div>
  );
}

function SummaryArticle({ summary }: { summary: ReaderSummary }) {
  return (
    <article>
      <div className="mb-3 flex flex-wrap items-center gap-2 text-xs font-semibold text-muted">
        <span>Page {summary.start_page} / {summary.end_page}</span>
        <span>·</span>
        <span>{summary.model}</span>
        <UsageCostBadges summary={summary} />
      </div>
      <p className="whitespace-pre-wrap text-right font-vazir text-sm leading-7 text-ink" dir="rtl">{summary.summary}</p>
    </article>
  );
}

function ConfirmDialog({
  title,
  body,
  confirmLabel,
  onCancel,
  onConfirm
}: {
  title: string;
  body: string;
  confirmLabel: string;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div className="app-no-drag fixed inset-0 z-[70] flex items-center justify-center bg-ink/35 px-5" onMouseDown={onCancel}>
      <section
        onMouseDown={(event) => event.stopPropagation()}
        className="w-full max-w-sm rounded-2xl border border-line bg-white p-5 shadow-2xl"
      >
        <div className="mb-4 flex items-start justify-between gap-4">
          <div>
            <h2 className="text-base font-semibold text-ink">{title}</h2>
            <p className="mt-2 text-sm leading-6 text-muted">{body}</p>
          </div>
          <button type="button" onClick={onCancel} className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg hover:bg-cream">
            <X size={17} />
          </button>
        </div>
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onCancel} className="h-10 rounded-xl px-4 text-sm font-semibold text-muted hover:bg-cream">
            Cancel
          </button>
          <button type="button" onClick={onConfirm} className="h-10 rounded-xl bg-red-700 px-4 text-sm font-semibold text-white hover:bg-red-800">
            {confirmLabel}
          </button>
        </div>
      </section>
    </div>
  );
}

function UsageCostBadges({ summary, compact = false, selected = false }: { summary: ReaderSummary; compact?: boolean; selected?: boolean }) {
  const cost = costDisplayText(summary);
  if (!cost) return (
    <span className={`inline-flex rounded-full px-2 py-0.5 text-[11px] font-semibold ${
      selected ? "bg-white/10 text-white/80" : compact ? "bg-ink/5 text-muted" : "bg-cream text-muted"
    }`}>
      cost not returned
    </span>
  );
  const className = selected
    ? "bg-white/10 text-white/80"
    : compact
      ? "bg-ink/5 text-muted"
      : "bg-cream text-muted";
  return (
    <span className={`inline-flex rounded-full px-2 py-0.5 text-[11px] font-semibold ${className}`}>
      {cost}
    </span>
  );
}

function GeneratedOutputsView({
  summaries,
  selectedSummary,
  pageSummaries,
  noteOutputs,
  onSelect,
  onDelete
}: {
  summaries: ReaderSummary[];
  selectedSummary: ReaderSummary | null;
  pageSummaries: ReaderSummary[];
  noteOutputs: ReaderSummary[];
  onSelect: (summary: ReaderSummary) => void;
  onDelete: (id: string) => void;
}) {
  return (
    <div className="grid min-h-0 flex-1 grid-cols-[260px_minmax(0,1fr)] gap-0">
      <div className="paper-scroll min-h-0 overflow-auto border-r border-line bg-paper p-3">
        {summaries.length ? (
          <>
            <GeneratedSummaryGroup
              title="Page summaries"
              items={pageSummaries}
              selectedId={selectedSummary?.id ?? null}
              onSelect={onSelect}
              onDelete={onDelete}
            />
            <GeneratedSummaryGroup
              title="From notes"
              items={noteOutputs}
              selectedId={selectedSummary?.id ?? null}
              onSelect={onSelect}
              onDelete={onDelete}
            />
          </>
        ) : (
          <div className="flex h-full min-h-32 items-center justify-center px-4 text-center text-sm leading-6 text-muted">
            No generated content yet.
          </div>
        )}
      </div>
      <div className="paper-scroll min-h-0 overflow-auto bg-white p-5">
        {selectedSummary ? (
          <SummaryArticle summary={selectedSummary} />
        ) : (
          <div className="flex h-full min-h-32 items-center justify-center text-center text-sm leading-6 text-muted">
            Select a generated output.
          </div>
        )}
      </div>
    </div>
  );
}

function GeneratedSummaryGroup({
  title,
  items,
  selectedId,
  onSelect,
  onDelete
}: {
  title: string;
  items: ReaderSummary[];
  selectedId: string | null;
  onSelect: (summary: ReaderSummary) => void;
  onDelete: (id: string) => void;
}) {
  if (!items.length) return null;
  return (
    <section className="mb-4">
      <h3 className="mb-2 px-1 text-xs font-bold uppercase tracking-wide text-muted">{title}</h3>
      {items.map((summary) => {
        const isSelected = selectedId === summary.id;
        return (
          <article
            key={summary.id}
            className={`group mb-2 rounded-xl border px-3 py-3 text-sm transition ${
              isSelected ? "border-ink bg-ink text-white shadow-sm" : "border-transparent bg-white/70 text-ink hover:bg-white"
            }`}
          >
            <button
              type="button"
              onClick={() => onSelect(summary)}
              className="block w-full text-left"
            >
              <span className={`block text-xs font-semibold ${isSelected ? "text-white/65" : "text-muted"}`}>
                Page {summary.start_page} / {summary.end_page}
              </span>
              <SummaryListTitle title={summaryTitle(summary)} />
              <div className="mt-2">
                <UsageCostBadges summary={summary} compact selected={isSelected} />
              </div>
            </button>
            <div className="mt-2 flex justify-end">
              <button
                type="button"
                onClick={() => onDelete(summary.id)}
                className={`inline-flex h-7 items-center gap-1 rounded-lg px-2 text-xs font-semibold ${
                  isSelected ? "text-white/75 hover:bg-white/10" : "text-red-700 hover:bg-red-50"
                }`}
              >
                <Trash2 size={13} />
                Delete
              </button>
            </div>
          </article>
        );
      })}
    </section>
  );
}

function SummaryListTitle({ title }: { title: string }) {
  const containerRef = useRef<HTMLSpanElement | null>(null);
  const textRef = useRef<HTMLSpanElement | null>(null);
  const [overflowDistance, setOverflowDistance] = useState(0);

  useEffect(() => {
    const measure = () => {
      const container = containerRef.current;
      const text = textRef.current;
      if (!container || !text) return;
      const textWidth = text.getBoundingClientRect().width;
      setOverflowDistance(Math.max(0, Math.ceil(textWidth - container.clientWidth + 16)));
    };
    measure();
    const observer = new ResizeObserver(measure);
    if (containerRef.current) observer.observe(containerRef.current);
    if (textRef.current) observer.observe(textRef.current);
    return () => observer.disconnect();
  }, [title]);

  return (
    <span ref={containerRef} className="summary-title-marquee mt-1 block text-right font-vazir text-sm font-semibold leading-6" dir="rtl">
      <span
        ref={textRef}
        className={overflowDistance ? "summary-title-marquee-text" : ""}
        style={{ "--summary-title-distance": `${overflowDistance}px` } as CSSProperties}
      >
        {title}
      </span>
    </span>
  );
}

function summaryTitle(summary: ReaderSummary) {
  if (summary.title?.trim()) return summary.title.trim();
  const firstLine = summary.summary
    .split(/\n+/)
    .map((line) => line.trim())
    .find(Boolean);
  if (!firstLine) return `Summary ${summary.start_page}-${summary.end_page}`;
  return firstLine.replace(/^[-•\s]+/, "").slice(0, 64);
}

function outputType(summary: ReaderSummary) {
  return summary.output_type === "notes" ? "notes" : "summary";
}

function costDisplayText(summary: ReaderSummary) {
  const cost = Number(summary.provider_cost);
  if (!Number.isFinite(cost)) return null;
  const currency = summary.cost_currency?.trim();
  const formatted = currency?.toLowerCase() === "toman"
    ? cost.toLocaleString(undefined, { maximumFractionDigits: 0 })
    : cost.toLocaleString(undefined, { maximumFractionDigits: 6 });
  return currency ? `${formatted} ${currency}` : `${formatted} provider cost`;
}

function NotesPanel({
  open,
  annotations,
  currentPageIndex,
  colorFilter,
  onColorFilterChange,
  onDelete,
  onGoTo
}: {
  open: boolean;
  annotations: ReaderAnnotation[];
  currentPageIndex: number;
  colorFilter: string | null;
  onColorFilterChange: (color: string | null) => void;
  onDelete: (id: string) => void;
  onGoTo: (annotation: ReaderAnnotation) => void;
}) {
  const filteredAnnotations = annotations.filter((annotation) => !colorFilter || normalizedHighlightColor(annotation.color) === colorFilter);

  return (
    <aside
      data-open={open}
      className={`notes-panel flex h-full min-h-0 w-80 flex-col overflow-hidden rounded-2xl border border-line bg-white shadow-soft transition-[transform,opacity] duration-300 ease-out ${
        open ? "translate-x-0 opacity-100" : "translate-x-full opacity-0"
      }`}
    >
      <div className="shrink-0 border-b border-line bg-paper px-5 py-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm font-semibold">Notes</h2>
            <p className="text-xs text-muted">{filteredAnnotations.length} of {annotations.length} saved</p>
          </div>
          <StickyNote size={18} className="text-muted" />
        </div>
        <div className="mt-3 flex items-center gap-2">
          <button
            type="button"
            onClick={() => onColorFilterChange(null)}
            className={`h-7 rounded-full border px-3 text-xs font-semibold ${
              colorFilter === null ? "border-ink bg-ink text-white" : "border-line bg-white text-muted hover:bg-cream"
            }`}
          >
            All
          </button>
          {HIGHLIGHT_COLORS.map((color) => (
            <button
              key={color.value}
              type="button"
              onClick={() => onColorFilterChange(color.value)}
              className={`h-7 w-7 rounded-full border ${
                colorFilter === color.value ? "border-ink ring-2 ring-ink/20" : "border-line hover:ring-2 hover:ring-ink/10"
              }`}
              style={{ backgroundColor: color.value }}
              title={color.label}
            />
          ))}
        </div>
      </div>
      <div className="paper-scroll min-h-0 flex-1 overflow-auto p-3">
        {filteredAnnotations.length ? (
          filteredAnnotations
            .slice()
            .sort((a, b) => a.page_index - b.page_index || String(b.updated_at || "").localeCompare(String(a.updated_at || "")))
            .map((annotation) => {
              const color = normalizedHighlightColor(annotation.color);
              return (
                <article
                  key={annotation.id}
                  className={`mb-3 rounded-xl border p-3 ${
                    annotation.page_index === currentPageIndex ? "border-ink/35" : "border-line"
                  }`}
                  style={{ backgroundColor: tintedHighlightColor(color) }}
                >
                  <button type="button" onClick={() => onGoTo(annotation)} className="block w-full text-left">
                    <div className="mb-2 flex items-center justify-between gap-2 text-xs font-semibold text-muted">
                      <span>
                        {annotation.side === "original" ? "Original" : "Translation"} · Page {annotation.page_index + 1}
                      </span>
                      {annotation.note ? <MessageSquare size={14} /> : <Highlighter size={14} />}
                    </div>
                    <p className="line-clamp-3 text-sm leading-6 text-ink">{annotation.selected_text}</p>
                    {annotation.note ? <p className="mt-2 rounded-lg bg-white/55 px-3 py-2 text-sm leading-6 text-ink">{annotation.note}</p> : null}
                  </button>
                  <div className="mt-3 flex justify-end">
                    <button
                      type="button"
                      onClick={() => onDelete(annotation.id)}
                      className="inline-flex h-8 items-center gap-1 rounded-lg px-2 text-xs font-semibold text-red-700 hover:bg-white/55"
                    >
                      <Trash2 size={14} />
                      Delete
                    </button>
                  </div>
                </article>
              );
            })
        ) : (
          <div className="flex h-full items-center justify-center px-6 text-center text-sm leading-6 text-muted">
            {annotations.length ? "No notes match this color." : "Select text in Original or Translation to save highlights and comments."}
          </div>
        )}
      </div>
    </aside>
  );
}

function ModeSwitch({ value, onChange, disabled }: { value: ViewMode; onChange: (value: ViewMode) => void; disabled: boolean }) {
  const modes: { value: ViewMode; label: string; icon: ReactNode }[] = [
    { value: "original", label: "Original", icon: <FileText size={16} /> },
    { value: "split", label: "Split", icon: <PanelLeftClose size={16} /> },
    { value: "translation", label: "Translation", icon: <BookOpen size={16} /> }
  ];

  return (
    <div className="ml-3 inline-flex shrink-0 rounded-xl border border-line bg-white p-1">
      {modes.map((mode) => (
        <button
          type="button"
          key={mode.value}
          disabled={disabled}
          onClick={() => onChange(mode.value)}
          className={`inline-flex h-8 items-center gap-2 whitespace-nowrap rounded-lg px-3 text-xs font-semibold ${
            value === mode.value ? "bg-ink text-white" : "text-muted hover:bg-cream"
          } disabled:opacity-35`}
        >
          {mode.icon}
          {mode.label}
        </button>
      ))}
    </div>
  );
}

function EmptyState({ isOpening, onOpen }: { isOpening: boolean; onOpen: () => void }) {
  return (
    <div className="mx-auto flex min-h-[70vh] max-w-xl flex-col items-center justify-center text-center">
      <div className="mb-7 flex h-32 w-32 items-center justify-center rounded-[32px] bg-white shadow-soft">
        <LogoMark large />
      </div>
      <h2 className="text-3xl font-bold">Open an MRBK to begin</h2>
      <p className="mt-4 max-w-md text-lg text-muted">Choose a Mirook book file and read original and translation side by side.</p>
      <button
        type="button"
        onClick={onOpen}
        disabled={isOpening}
        className="mt-8 inline-flex h-12 items-center gap-2 rounded-xl bg-ink px-7 text-sm font-semibold text-white hover:bg-black disabled:opacity-55"
      >
        {isOpening ? <Loader2 className="animate-spin" size={19} /> : <FolderOpen size={19} />}
        Open MRBK
      </button>
    </div>
  );
}

function LogoMark({ large = false }: { large?: boolean }) {
  const size = large ? "h-20 w-20" : "h-10 w-10";
  return (
    <img src="/mirook-logo-mark.png" alt="" aria-hidden="true" className={`${size} shrink-0 object-contain`} />
  );
}

function firstReadablePage(payload: MirookBookPayload) {
  return payload.pages.find((page) => page.translatedText?.trim() || page.isBlank)?.pageIndex ?? 0;
}

function isViewMode(value: unknown): value is ViewMode {
  return value === "split" || value === "original" || value === "translation";
}

function clampPageIndex(index: number, pageCount: number) {
  if (!pageCount) return 0;
  return Math.min(pageCount - 1, Math.max(0, Math.trunc(index)));
}

function clampPageNumber(pageNumber: number, pageCount: number) {
  if (!pageCount) return 1;
  const normalized = Number.isFinite(pageNumber) ? Math.trunc(pageNumber) : 1;
  return Math.min(pageCount, Math.max(1, normalized));
}

function summaryTextForRange(book: MirookBookPayload, startPage: number, endPage: number) {
  const startIndex = clampPageNumber(startPage, book.manifest.pageCount) - 1;
  const endIndex = clampPageNumber(endPage, book.manifest.pageCount) - 1;
  const first = Math.min(startIndex, endIndex);
  const last = Math.max(startIndex, endIndex);

  return book.pages
    .filter((page) => page.pageIndex >= first && page.pageIndex <= last)
    .map((page) => {
      const translated = translationParagraphs(page).join("\n\n").trim();
      const sourceBlocks = pageAlignedSourceBlocks(book.epubPages, page);
      const source = sourcePlainText(sourceBlocks, page.sourceText ?? "");
      const text = translated || source;
      return text ? `Page ${page.pageIndex + 1}\n${text}` : "";
    })
    .filter(Boolean)
    .join("\n\n---\n\n");
}

function notesForRange(
  annotations: ReaderAnnotation[],
  startPage: number,
  endPage: number,
  color: string | null,
  notesOnly: boolean
) {
  const startIndex = Math.min(startPage, endPage) - 1;
  const endIndex = Math.max(startPage, endPage) - 1;
  return annotations
    .filter((annotation) => annotation.page_index >= startIndex && annotation.page_index <= endIndex)
    .filter((annotation) => !color || normalizedHighlightColor(annotation.color) === color)
    .filter((annotation) => !notesOnly || Boolean(annotation.note?.trim()))
    .sort((a, b) => a.page_index - b.page_index || String(a.created_at || "").localeCompare(String(b.created_at || "")));
}

function notesTextForRange(
  annotations: ReaderAnnotation[],
  startPage: number,
  endPage: number,
  color: string | null,
  notesOnly: boolean
) {
  return notesForRange(annotations, startPage, endPage, color, notesOnly)
    .map((annotation, index) => {
      const note = annotation.note?.trim();
      const selectedText = annotation.selected_text?.trim();
      return [
        `Item ${index + 1} · Page ${annotation.page_index + 1} · ${annotation.side}`,
        selectedText ? `Highlight: ${selectedText}` : "",
        note ? `Note: ${note}` : ""
      ].filter(Boolean).join("\n");
    })
    .join("\n\n---\n\n");
}

function normalizedHighlightColor(color?: string | null) {
  return color || HIGHLIGHT_COLORS[0].value;
}

function tintedHighlightColor(color: string) {
  const known = HIGHLIGHT_COLORS.find((item) => item.value === color)?.value ?? HIGHLIGHT_COLORS[0].value;
  return `${known}66`;
}

function textBlockId(side: AnnotationSide, pageIndex: number, blockIndex: number) {
  return `${side}:${pageIndex}:${blockIndex}`;
}

function annotationsForBlock(annotations: ReaderAnnotation[], blockId: string) {
  return annotations.filter((annotation) => annotation.block_id === blockId);
}

function annotationsForTextRange(annotations: ReaderAnnotation[], start: number, end: number) {
  return annotations
    .filter((annotation) => Number(annotation.end_offset) > start && Number(annotation.start_offset) < end)
    .map((annotation) => ({
      ...annotation,
      start_offset: Math.max(0, Number(annotation.start_offset) - start),
      end_offset: Math.min(end - start, Number(annotation.end_offset) - start)
    }));
}

function originalPdfLines(text: string) {
  const rawLines = text
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split("\n")
    .map((line) => line.trimEnd())
    .filter((line) => line.trim());

  return rawLines.map((raw, index) => {
    const trimmed = raw.trim();
    const previous = index > 0 ? rawLines[index - 1].trim() : "";
    const previousLooksClosed = /[.!?؟:;؛)"”»\]]$/.test(previous);
    const heading = isOriginalHeadingLine(trimmed);
    const previousHeading = previous ? isOriginalHeadingLine(previous) : false;
    const indented =
      index > 0 &&
      !heading &&
      !previousHeading &&
      previousLooksClosed &&
      !/^(?:\(|\[|["“])/.test(trimmed);

    return { raw: trimmed, indented, heading };
  });
}

function isOriginalHeadingLine(text: string) {
  if (/^\d+\.\s+\S/.test(text)) return true;
  if (/^\d+$/.test(text)) return true;
  if (text.length > 90 || /[.!?؟;؛]$/.test(text)) return false;
  const words = text.split(/\s+/).filter(Boolean);
  if (words.length > 8) return false;
  return words.some((word) => /^[A-Z0-9]/.test(word));
}

function isTranslationHeadingLine(text: string) {
  const trimmed = text.trim();
  if (!trimmed) return false;
  if (/^[\d۰-۹٠-٩]+$/.test(trimmed)) return true;
  if (/^[\d۰-۹٠-٩]+[.)،]\s+\S/.test(trimmed)) return true;
  if (trimmed.length > 90 || /[.!?؟:؛;،,]$/.test(trimmed)) return false;
  const words = trimmed.split(/\s+/).filter(Boolean);
  return words.length <= 8;
}

function hasActiveTextSelection() {
  const selection = window.getSelection();
  return Boolean(selection && !selection.isCollapsed && selection.toString().trim());
}

function selectionFromWindow(side: AnnotationSide, pageIndex: number, point?: { x: number; y: number }): SelectionState | null {
  const currentSelection = window.getSelection();
  if (!currentSelection || currentSelection.rangeCount === 0 || currentSelection.isCollapsed) return null;
  const range = currentSelection.getRangeAt(0);
  const startBlock = closestAnnotationBlock(range.startContainer);
  const endBlock = closestAnnotationBlock(range.endContainer);
  if (!startBlock || !endBlock || startBlock !== endBlock) return null;

  const offsets = rangeOffsetsWithin(startBlock, range);
  if (!offsets || offsets.end <= offsets.start) return null;
  const selectedText = startBlock.textContent?.slice(offsets.start, offsets.end).trim() || "";
  if (!selectedText) return null;

  const rect = range.getBoundingClientRect();
  const position = clampedPopoverPosition(point?.x ?? rect.left + rect.width / 2, point?.y ?? rect.bottom + 8);
  return {
    x: position.x,
    y: position.y,
    pageIndex,
    side,
    blockId: startBlock.dataset.annotationBlockId || "",
    startOffset: offsets.start,
    endOffset: offsets.end,
    selectedText
  };
}

function clampedPopoverPosition(x: number, y: number) {
  const width = 320;
  const height = 286;
  const margin = 12;
  return {
    x: Math.max(margin, Math.min(window.innerWidth - width - margin, x)),
    y: Math.max(margin, Math.min(window.innerHeight - height - margin, y))
  };
}

function closestAnnotationBlock(node: Node) {
  const element = node.nodeType === Node.ELEMENT_NODE ? (node as Element) : node.parentElement;
  return element?.closest<HTMLElement>("[data-annotation-block-id]") ?? null;
}

function rangeOffsetsWithin(container: HTMLElement, range: Range) {
  const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
  let offset = 0;
  let start: number | null = null;
  let end: number | null = null;
  let node = walker.nextNode();
  while (node) {
    const length = node.textContent?.length ?? 0;
    if (node === range.startContainer) start = offset + range.startOffset;
    if (node === range.endContainer) end = offset + range.endOffset;
    offset += length;
    node = walker.nextNode();
  }
  if (start == null || end == null) return null;
  return start <= end ? { start, end } : { start: end, end: start };
}

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  return String(error);
}
