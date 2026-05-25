import { useEffect, useMemo, useRef, useState } from "react";
import { BookOpen, ChevronLeft, ChevronRight, FileText, FolderOpen, Loader2, Minus, PanelLeftClose, Plus } from "lucide-react";
import type { DisplayBlock } from "./readerBlocks";
import { sourcePlainText, translatedDisplayBlocks } from "./readerBlocks";
import type { EpubBlock, MirookBookPayload, TranslatedTextPage } from "./types";

type ViewMode = "split" | "original" | "translation";

export function App() {
  const [book, setBook] = useState<MirookBookPayload | null>(null);
  const [pageIndex, setPageIndex] = useState(0);
  const [fontSize, setFontSize] = useState(() => Number(localStorage.getItem("mirook-reader-font-size") ?? 22));
  const [viewMode, setViewMode] = useState<ViewMode>("split");
  const [error, setError] = useState<string | null>(null);
  const [isOpening, setIsOpening] = useState(false);
  const scrollRef = useRef<HTMLDivElement | null>(null);

  const pageCount = book?.manifest.pageCount ?? 0;
  const page = useMemo(() => book?.pages.find((item) => item.pageIndex === pageIndex), [book, pageIndex]);
  const epubPage = book?.epubPages[pageIndex];
  const sourceBlocks = epubPage?.blocks;
  const title = book?.manifest.displayName ?? "Mirook Reader";
  const sourceKind = String(book?.manifest.sourceKind ?? "pdf").toLowerCase();
  const hasBook = Boolean(book);
  const canGoPrevious = pageIndex > 0;
  const canGoNext = pageCount ? pageIndex < pageCount - 1 : false;

  useEffect(() => {
    localStorage.setItem("mirook-reader-font-size", String(fontSize));
  }, [fontSize]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0 });
  }, [pageIndex, viewMode, book?.id]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!hasBook) return;
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
      const file = event.dataTransfer?.files?.[0] as (File & { path?: string }) | undefined;
      if (!file?.path) {
        setError("Electron could not read the dropped file path. Use Open MRBK.");
        return;
      }
      await openPath(file.path);
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
    try {
      const payload = await window.mirook.openBook();
      if (payload) {
        setBook(payload);
        setPageIndex(firstReadablePage(payload));
        setViewMode("split");
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
    try {
      const payload = await window.mirook.openBookPath(path);
      setBook(payload);
      setPageIndex(firstReadablePage(payload));
      setViewMode("split");
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setIsOpening(false);
    }
  }

  return (
    <div className="flex h-full w-full flex-col overflow-hidden bg-cream text-ink">
      <header className="flex h-16 shrink-0 items-center justify-between border-b border-line bg-paper/90 px-8">
        <div className="flex min-w-0 items-center gap-4">
          <LogoMark />
          <div className="min-w-0">
            <h1 className="truncate text-base font-semibold">{hasBook ? title : "Mirook Reader"}</h1>
            <p className="text-xs text-muted">
              {hasBook ? `${sourceKind.toUpperCase()} source · Page ${pageIndex + 1} of ${pageCount}` : "Open an MRBK file to begin"}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => setFontSize((value) => Math.max(14, value - 1))}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-line bg-white hover:bg-cream"
            title="Smaller text"
          >
            <Minus size={18} />
          </button>
          <span className="w-8 text-center text-sm text-muted">{fontSize}</span>
          <button
            type="button"
            onClick={() => setFontSize((value) => Math.min(36, value + 1))}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-line bg-white hover:bg-cream"
            title="Larger text"
          >
            <Plus size={18} />
          </button>
          <ModeSwitch value={viewMode} onChange={setViewMode} disabled={!hasBook} />
          <button
            type="button"
            onClick={openBook}
            disabled={isOpening}
            className="ml-2 inline-flex h-10 items-center gap-2 rounded-lg bg-ink px-4 text-sm font-semibold text-white shadow-sm hover:bg-black disabled:opacity-55"
          >
            {isOpening ? <Loader2 className="animate-spin" size={18} /> : <FolderOpen size={18} />}
            Open MRBK
          </button>
        </div>
      </header>

      {error ? (
        <div className="mx-8 mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>
      ) : null}

      <main ref={scrollRef} className="paper-scroll min-h-0 flex-1 overflow-auto px-8 py-7">
        {!book ? (
          <EmptyState isOpening={isOpening} onOpen={openBook} />
        ) : (
          <ReaderLayout
            book={book}
            page={page}
            pageIndex={pageIndex}
            sourceBlocks={sourceBlocks}
            fontSize={fontSize}
            viewMode={viewMode}
          />
        )}
      </main>

      <footer className="flex h-20 shrink-0 items-center justify-center border-t border-line bg-paper/90 px-8">
        <div className="flex w-full max-w-5xl items-center justify-between rounded-2xl border border-line bg-white/80 p-2 shadow-sm">
          <button
            type="button"
            disabled={!canGoPrevious}
            onClick={() => setPageIndex((value) => Math.max(0, value - 1))}
            className="inline-flex h-11 items-center gap-2 rounded-xl px-5 text-sm font-medium hover:bg-cream disabled:opacity-35"
          >
            <ChevronLeft size={20} />
            Previous
          </button>
          <div className="text-sm font-semibold text-muted">{hasBook ? `Page ${pageIndex + 1} / ${pageCount}` : "No book open"}</div>
          <button
            type="button"
            disabled={!canGoNext}
            onClick={() => setPageIndex((value) => Math.min(pageCount - 1, value + 1))}
            className="inline-flex h-11 items-center gap-2 rounded-xl px-5 text-sm font-medium hover:bg-cream disabled:opacity-35"
          >
            Next
            <ChevronRight size={20} />
          </button>
        </div>
      </footer>
    </div>
  );
}

function ReaderLayout({
  book,
  page,
  pageIndex,
  sourceBlocks,
  fontSize,
  viewMode
}: {
  book: MirookBookPayload;
  page?: TranslatedTextPage;
  pageIndex: number;
  sourceBlocks?: EpubBlock[];
  fontSize: number;
  viewMode: ViewMode;
}) {
  const translatedBlocks = translatedDisplayBlocks(sourceBlocks, page);
  const sourceText = sourcePlainText(sourceBlocks, page?.sourceText ?? "");
  const showOriginal = viewMode === "split" || viewMode === "original";
  const showTranslation = viewMode === "split" || viewMode === "translation";

  return (
    <div
      className={
        viewMode === "split"
          ? "mx-auto grid max-w-[1480px] grid-cols-2 gap-5"
          : "mx-auto grid max-w-[900px] grid-cols-1"
      }
    >
      {showOriginal ? (
        <Paper title="Original" pageIndex={pageIndex}>
          {book.manifest.sourceKind === "pdf" && book.sourcePdf ? (
            <iframe src={book.sourcePdf} className="h-[72vh] w-full rounded-lg border border-line bg-white" title="Original PDF" />
          ) : sourceBlocks?.length ? (
            <BlockFlow blocks={sourceBlocks} fontSize={fontSize} direction="ltr" />
          ) : (
            <TextFlow text={sourceText || "No source text for this page."} fontSize={fontSize} direction="ltr" />
          )}
        </Paper>
      ) : null}

      {showTranslation ? (
        <Paper title="Translation" pageIndex={pageIndex}>
          {page?.isBlank ? (
            <div className="flex min-h-[55vh] items-center justify-center text-center text-muted">Blank source page</div>
          ) : translatedBlocks.length ? (
            <DisplayFlow blocks={translatedBlocks} fontSize={fontSize} />
          ) : (
            <div className="flex min-h-[55vh] items-center justify-center text-center text-muted">No translation for this page yet.</div>
          )}
        </Paper>
      ) : null}
    </div>
  );
}

function Paper({ title, pageIndex, children }: { title: string; pageIndex: number; children: React.ReactNode }) {
  return (
    <section className="min-w-0 overflow-hidden rounded-2xl border border-line bg-white shadow-soft">
      <div className="flex items-center justify-between border-b border-line bg-paper px-6 py-4">
        <h2 className="text-sm font-semibold">{title}</h2>
        <span className="text-sm text-muted">Page {pageIndex + 1}</span>
      </div>
      <div className="min-h-[68vh] bg-white px-12 py-10">{children}</div>
    </section>
  );
}

function DisplayFlow({ blocks, fontSize }: { blocks: DisplayBlock[]; fontSize: number }) {
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
        return (
          <p key={index} className="mb-5 whitespace-pre-wrap text-right">
            {block.text}
          </p>
        );
      })}
    </div>
  );
}

function BlockFlow({ blocks, fontSize, direction }: { blocks: EpubBlock[]; fontSize: number; direction: "rtl" | "ltr" }) {
  return (
    <div className={direction === "rtl" ? "font-vazir" : "font-serif"} dir={direction} style={{ fontSize, lineHeight: 1.75 }}>
      {blocks.map((block, index) => {
        if (block.type === "image") return <BookImage key={index} src={block.src} alt={block.altText ?? ""} />;
        if (block.type === "link") {
          return (
            <p key={index} className="mb-5">
              <a className="text-blue-700 underline" href={block.href}>
                {block.title}
              </a>
            </p>
          );
        }
        return (
          <p key={index} className="mb-5 whitespace-pre-wrap">
            {block.text}
          </p>
        );
      })}
    </div>
  );
}

function TextFlow({ text, fontSize, direction }: { text: string; fontSize: number; direction: "rtl" | "ltr" }) {
  return (
    <div className={direction === "rtl" ? "font-vazir" : "font-serif"} dir={direction} style={{ fontSize, lineHeight: 1.8 }}>
      {text.split(/\n{2,}/).map((paragraph, index) => (
        <p key={index} className="mb-5 whitespace-pre-wrap">
          {paragraph}
        </p>
      ))}
    </div>
  );
}

function BookImage({ src, alt }: { src: string; alt: string }) {
  return (
    <figure className="my-8 flex w-full flex-col items-center">
      <img src={src} alt={alt} className="max-h-[640px] max-w-full object-contain" />
      {alt ? <figcaption className="mt-2 text-center text-sm text-muted">{alt}</figcaption> : null}
    </figure>
  );
}

function ModeSwitch({ value, onChange, disabled }: { value: ViewMode; onChange: (value: ViewMode) => void; disabled: boolean }) {
  const modes: { value: ViewMode; label: string; icon: React.ReactNode }[] = [
    { value: "original", label: "Original", icon: <FileText size={16} /> },
    { value: "split", label: "Split", icon: <PanelLeftClose size={16} /> },
    { value: "translation", label: "Translation", icon: <BookOpen size={16} /> }
  ];

  return (
    <div className="ml-3 inline-flex rounded-xl border border-line bg-white p-1">
      {modes.map((mode) => (
        <button
          type="button"
          key={mode.value}
          disabled={disabled}
          onClick={() => onChange(mode.value)}
          className={`inline-flex h-8 items-center gap-2 rounded-lg px-3 text-xs font-semibold ${
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
  const size = large ? "h-16 w-16" : "h-9 w-9";
  return (
    <div className={`${size} relative shrink-0`}>
      <svg viewBox="0 0 64 64" aria-hidden="true" className="h-full w-full">
        <path d="M10 48V16l22 21 22-21v32" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="6" />
      </svg>
    </div>
  );
}

function firstReadablePage(payload: MirookBookPayload) {
  return payload.pages.find((page) => page.translatedText?.trim() || page.isBlank)?.pageIndex ?? 0;
}

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  return String(error);
}
