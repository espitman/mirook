const { app, BrowserWindow, dialog, ipcMain } = require("electron");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const JSZip = require("jszip");
const initSqlJs = require("sql.js");

let mainWindow;
let sqlPromise;
let readerDb;
let readerDbPath;

function appRoot() {
  return app.getAppPath();
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 960,
    minWidth: 980,
    minHeight: 680,
    backgroundColor: "#f4efe6",
    title: "Mirook Reader",
    titleBarStyle: "hiddenInset",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  const devServerUrl = process.env.VITE_DEV_SERVER_URL;
  if (devServerUrl) {
    mainWindow.loadURL(devServerUrl);
  } else {
    mainWindow.loadFile(path.join(appRoot(), "dist", "index.html"));
  }
}

async function getSql() {
  if (!sqlPromise) {
    sqlPromise = initSqlJs({
      locateFile: (file) => path.join(appRoot(), "node_modules", "sql.js", "dist", file)
    });
  }
  return sqlPromise;
}

function oneValue(db, query, params = {}) {
  const statement = db.prepare(query);
  try {
    statement.bind(params);
    if (!statement.step()) return null;
    return statement.get()[0] ?? null;
  } finally {
    statement.free();
  }
}

function allRows(db, query, params = {}) {
  const statement = db.prepare(query);
  const rows = [];
  try {
    statement.bind(params);
    while (statement.step()) rows.push(statement.getAsObject());
    return rows;
  } finally {
    statement.free();
  }
}

function run(db, query, params = {}) {
  const statement = db.prepare(query);
  try {
    statement.bind(params);
    statement.step();
  } finally {
    statement.free();
  }
}

function bytesToString(value) {
  if (value == null) return "";
  if (typeof value === "string") return value;
  return new TextDecoder().decode(value);
}

function normalizeBytes(value) {
  if (value == null) return null;
  if (value instanceof Uint8Array) return value;
  if (Array.isArray(value)) return Uint8Array.from(value);
  if (Buffer.isBuffer(value)) return new Uint8Array(value);
  if (typeof value === "string") return new TextEncoder().encode(value);
  return null;
}

function dataUrl(bytes, mimeType) {
  return `data:${mimeType};base64,${Buffer.from(bytes).toString("base64")}`;
}

async function getReaderDb() {
  if (readerDb) return readerDb;
  const SQL = await getSql();
  readerDbPath = path.join(app.getPath("userData"), "reader.sqlite");
  if (fs.existsSync(readerDbPath)) {
    readerDb = new SQL.Database(fs.readFileSync(readerDbPath));
  } else {
    readerDb = new SQL.Database();
  }
  readerDb.exec(`
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS books (
      id TEXT PRIMARY KEY,
      fingerprint TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      file_path TEXT NOT NULL,
      source_kind TEXT,
      page_count INTEGER NOT NULL DEFAULT 0,
      manifest_json TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_opened_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS reading_positions (
      book_id TEXT PRIMARY KEY,
      page_index INTEGER NOT NULL DEFAULT 0,
      view_mode TEXT NOT NULL DEFAULT 'split',
      font_size INTEGER,
      scroll_original REAL NOT NULL DEFAULT 0,
      scroll_translation REAL NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS annotations (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      page_index INTEGER NOT NULL,
      side TEXT NOT NULL,
      block_id TEXT NOT NULL,
      start_offset INTEGER NOT NULL,
      end_offset INTEGER NOT NULL,
      selected_text TEXT NOT NULL,
      color TEXT,
      note TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS bookmarks (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      page_index INTEGER NOT NULL,
      title TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY,
      value TEXT,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS ai_summaries (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      start_page INTEGER NOT NULL,
      end_page INTEGER NOT NULL,
      model TEXT NOT NULL,
      summary TEXT NOT NULL,
      output_type TEXT NOT NULL DEFAULT 'summary',
      title TEXT,
      input_tokens INTEGER NOT NULL DEFAULT 0,
      output_tokens INTEGER NOT NULL DEFAULT 0,
      total_tokens INTEGER NOT NULL DEFAULT 0,
      provider_cost REAL,
      cost_currency TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
    );
  `);
  ensureColumn(readerDb, "ai_summaries", "output_type", "TEXT NOT NULL DEFAULT 'summary'");
  ensureColumn(readerDb, "ai_summaries", "title", "TEXT");
  ensureColumn(readerDb, "ai_summaries", "input_tokens", "INTEGER NOT NULL DEFAULT 0");
  ensureColumn(readerDb, "ai_summaries", "output_tokens", "INTEGER NOT NULL DEFAULT 0");
  ensureColumn(readerDb, "ai_summaries", "total_tokens", "INTEGER NOT NULL DEFAULT 0");
  ensureColumn(readerDb, "ai_summaries", "provider_cost", "REAL");
  ensureColumn(readerDb, "ai_summaries", "cost_currency", "TEXT");
  saveReaderDb();
  return readerDb;
}

function ensureColumn(db, table, column, definition) {
  const columns = allRows(db, `PRAGMA table_info(${table})`);
  if (columns.some((row) => row.name === column)) return;
  db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
}

function saveReaderDb() {
  if (!readerDb || !readerDbPath) return;
  fs.mkdirSync(path.dirname(readerDbPath), { recursive: true });
  fs.writeFileSync(readerDbPath, Buffer.from(readerDb.export()));
}

async function upsertBookRecord(payload) {
  const db = await getReaderDb();
  const now = new Date().toISOString();
  run(
    db,
    `INSERT INTO books (id, fingerprint, title, file_path, source_kind, page_count, manifest_json, created_at, updated_at, last_opened_at)
     VALUES ($id, $fingerprint, $title, $filePath, $sourceKind, $pageCount, $manifestJson, $now, $now, $now)
     ON CONFLICT(id) DO UPDATE SET
       fingerprint = excluded.fingerprint,
       title = excluded.title,
       file_path = excluded.file_path,
       source_kind = excluded.source_kind,
       page_count = excluded.page_count,
       manifest_json = excluded.manifest_json,
       updated_at = excluded.updated_at,
       last_opened_at = excluded.last_opened_at`,
    {
      $id: payload.id,
      $fingerprint: payload.fingerprint,
      $title: payload.manifest.displayName || path.basename(payload.filePath),
      $filePath: payload.filePath,
      $sourceKind: String(payload.manifest.sourceKind || ""),
      $pageCount: Number(payload.manifest.pageCount || payload.pages.length || 0),
      $manifestJson: JSON.stringify(payload.manifest),
      $now: now
    }
  );
  saveReaderDb();
}

async function readerStateForBook(bookId) {
  const db = await getReaderDb();
  const position = allRows(db, "SELECT * FROM reading_positions WHERE book_id = $bookId LIMIT 1", { $bookId: bookId })[0] ?? null;
  const annotations = allRows(db, "SELECT * FROM annotations WHERE book_id = $bookId ORDER BY page_index ASC, created_at ASC", { $bookId: bookId });
  const bookmarks = allRows(db, "SELECT * FROM bookmarks WHERE book_id = $bookId ORDER BY page_index ASC, created_at ASC", { $bookId: bookId });
  const summaries = allRows(db, "SELECT * FROM ai_summaries WHERE book_id = $bookId ORDER BY created_at DESC", { $bookId: bookId });
  return { position, annotations, bookmarks, summaries };
}

function annotationById(db, id) {
  return allRows(db, "SELECT * FROM annotations WHERE id = $id LIMIT 1", { $id: id })[0] ?? null;
}

async function saveAnnotation(annotation) {
  if (!annotation?.bookId) throw new Error("No book is open.");
  if (!annotation.blockId || !annotation.selectedText) throw new Error("Select text before saving an annotation.");
  const db = await getReaderDb();
  const now = new Date().toISOString();
  const id = annotation.id || crypto.randomUUID();
  run(
    db,
    `INSERT INTO annotations (id, book_id, page_index, side, block_id, start_offset, end_offset, selected_text, color, note, created_at, updated_at)
     VALUES ($id, $bookId, $pageIndex, $side, $blockId, $startOffset, $endOffset, $selectedText, $color, $note, $now, $now)
     ON CONFLICT(id) DO UPDATE SET
       page_index = excluded.page_index,
       side = excluded.side,
       block_id = excluded.block_id,
       start_offset = excluded.start_offset,
       end_offset = excluded.end_offset,
       selected_text = excluded.selected_text,
       color = excluded.color,
       note = excluded.note,
       updated_at = excluded.updated_at`,
    {
      $id: id,
      $bookId: annotation.bookId,
      $pageIndex: Number(annotation.pageIndex || 0),
      $side: String(annotation.side || "translation"),
      $blockId: String(annotation.blockId),
      $startOffset: Number(annotation.startOffset || 0),
      $endOffset: Number(annotation.endOffset || 0),
      $selectedText: String(annotation.selectedText),
      $color: annotation.color || "#fde68a",
      $note: annotation.note || null,
      $now: now
    }
  );
  saveReaderDb();
  return annotationById(db, id);
}

async function deleteAnnotation(id) {
  if (!id) return false;
  const db = await getReaderDb();
  run(db, "DELETE FROM annotations WHERE id = $id", { $id: id });
  saveReaderDb();
  return true;
}

async function deleteAiOutput(id) {
  if (!id) return false;
  const db = await getReaderDb();
  run(db, "DELETE FROM ai_summaries WHERE id = $id", { $id: id });
  saveReaderDb();
  return true;
}

async function exportBookData(bookId) {
  const db = await getReaderDb();
  const book = allRows(db, "SELECT * FROM books WHERE id = $bookId LIMIT 1", { $bookId: bookId })[0];
  if (!book) throw new Error("No local reader data was found for this book.");
  const state = await readerStateForBook(bookId);
  const payload = {
    schemaVersion: 1,
    exportedAt: new Date().toISOString(),
    book: {
      id: book.id,
      fingerprint: book.fingerprint,
      title: book.title,
      filePath: book.file_path,
      sourceKind: book.source_kind,
      pageCount: book.page_count,
      manifest: JSON.parse(book.manifest_json)
    },
    readingPosition: state.position,
    annotations: state.annotations,
    bookmarks: state.bookmarks,
    summaries: state.summaries
  };

  const result = await dialog.showSaveDialog(mainWindow, {
    title: "Export reader data",
    defaultPath: `${safeFileName(book.title || "mirook-book")}.mirook-notes.json`,
    filters: [{ name: "Mirook Notes JSON", extensions: ["json"] }]
  });
  if (result.canceled || !result.filePath) return null;
  fs.writeFileSync(result.filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  return result.filePath;
}

async function getAiSettings() {
  const db = await getReaderDb();
  const raw = oneValue(db, "SELECT value FROM app_settings WHERE key = 'liara_ai' LIMIT 1");
  if (!raw) return { url: "", apiKey: "", model: "openai/gpt-5-nano" };
  try {
    const parsed = JSON.parse(String(raw));
    return {
      url: typeof parsed.url === "string" ? parsed.url : "",
      apiKey: typeof parsed.apiKey === "string" ? parsed.apiKey : "",
      model: typeof parsed.model === "string" && parsed.model ? parsed.model : "openai/gpt-5-nano"
    };
  } catch {
    return { url: "", apiKey: "", model: "openai/gpt-5-nano" };
  }
}

async function saveAiSettings(settings) {
  const db = await getReaderDb();
  const normalized = {
    url: String(settings?.url || "").trim(),
    apiKey: String(settings?.apiKey || "").trim(),
    model: String(settings?.model || "openai/gpt-5-nano").trim()
  };
  run(
    db,
    `INSERT INTO app_settings (key, value, updated_at)
     VALUES ('liara_ai', $value, $updatedAt)
     ON CONFLICT(key) DO UPDATE SET
       value = excluded.value,
       updated_at = excluded.updated_at`,
    {
      $value: JSON.stringify(normalized),
      $updatedAt: new Date().toISOString()
    }
  );
  saveReaderDb();
  return normalized;
}

async function summarizePages(request) {
  if (!request?.bookId) throw new Error("No book is open.");
  const settings = await getAiSettings();
  if (!settings.url) throw new Error("Add a Liara URL in Settings first.");
  if (!settings.apiKey) throw new Error("Add a Liara API key in Settings first.");

  const inputText = String(request.text || "").trim();
  if (!inputText) throw new Error("No text was found in this page range.");

  const model = settings.model || "openai/gpt-5-nano";
  const result = await requestAiCompletion(settings, [
    {
      role: "system",
      content: "You summarize book passages for a Persian reader. Write concise, useful Persian summaries. Preserve important names, terms, and concrete ideas."
    },
    {
      role: "user",
      content: `این متن از صفحه ${request.startPage} تا ${request.endPage} کتاب است. یک خلاصه فارسی منظم و کاربردی بده:\n\n${inputText}`
    }
  ]);

  return saveAiOutput({
    bookId: request.bookId,
    startPage: Number(request.startPage || 1),
    endPage: Number(request.endPage || request.startPage || 1),
    model,
    summary: result.text,
    usage: result.usage,
    outputType: "summary",
    title: `Summary ${request.startPage}-${request.endPage}`
  });
}

async function generateTextFromNotes(request) {
  if (!request?.bookId) throw new Error("No book is open.");
  const settings = await getAiSettings();
  if (!settings.url) throw new Error("Add a Liara URL in Settings first.");
  if (!settings.apiKey) throw new Error("Add a Liara API key in Settings first.");

  const inputText = String(request.text || "").trim();
  if (!inputText) throw new Error("No notes or highlights matched this filter.");

  const model = settings.model || "openai/gpt-5-nano";
  const result = await requestAiCompletion(settings, [
    {
      role: "system",
      content: "You turn a reader's notes and highlights into a coherent Persian text. Use the notes as the main signal, preserve key quoted ideas, and avoid inventing facts."
    },
    {
      role: "user",
      content: `از یادداشت‌ها و هایلایت‌های زیر یک متن فارسی منسجم، خواندنی و کاربردی بساز. متن را با تیتر کوتاه شروع کن و بعد چند پاراگراف منظم بنویس:\n\n${inputText}`
    }
  ]);

  return saveAiOutput({
    bookId: request.bookId,
    startPage: Number(request.startPage || 1),
    endPage: Number(request.endPage || request.startPage || 1),
    model,
    summary: result.text,
    usage: result.usage,
    outputType: "notes",
    title: `Notes ${request.startPage}-${request.endPage}`
  });
}

async function requestAiCompletion(settings, messages) {
  const response = await fetch(chatCompletionsUrl(settings.url), {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${settings.apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: settings.model || "openai/gpt-5-nano",
      messages
    })
  });

  const payloadText = await response.text();
  let payload;
  try {
    payload = payloadText ? JSON.parse(payloadText) : {};
  } catch {
    payload = { raw: payloadText };
  }
  if (!response.ok) {
    const message = payload?.error?.message || payload?.message || payloadText || `AI request failed with status ${response.status}.`;
    throw new Error(message);
  }

  const text = payload?.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error("The AI response did not include a summary.");
  return {
    text,
    usage: aiUsageFromPayload(payload)
  };
}

async function saveAiOutput({ bookId, startPage, endPage, model, summary, usage, outputType, title }) {
  const db = await getReaderDb();
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  run(
    db,
    `INSERT INTO ai_summaries (
       id, book_id, start_page, end_page, model, summary, output_type, title,
       input_tokens, output_tokens, total_tokens, provider_cost, cost_currency, created_at
     )
     VALUES (
       $id, $bookId, $startPage, $endPage, $model, $summary, $outputType, $title,
       $inputTokens, $outputTokens, $totalTokens, $providerCost, $costCurrency, $createdAt
     )`,
    {
      $id: id,
      $bookId: bookId,
      $startPage: startPage,
      $endPage: endPage,
      $model: model,
      $summary: summary,
      $outputType: outputType,
      $title: title,
      $inputTokens: Number(usage?.inputTokens || 0),
      $outputTokens: Number(usage?.outputTokens || 0),
      $totalTokens: Number(usage?.totalTokens || 0),
      $providerCost: usage?.providerCost == null ? null : Number(usage.providerCost),
      $costCurrency: usage?.costCurrency || null,
      $createdAt: now
    }
  );
  saveReaderDb();
  return allRows(db, "SELECT * FROM ai_summaries WHERE id = $id LIMIT 1", { $id: id })[0];
}

function aiUsageFromPayload(payload) {
  const usage = payload?.usage || {};
  const inputTokens = Number(usage.prompt_tokens ?? usage.input_tokens ?? 0);
  const outputTokens = Number(usage.completion_tokens ?? usage.output_tokens ?? 0);
  const totalTokens = Number(usage.total_tokens ?? (inputTokens + outputTokens));
  const cost = providerReportedCost(payload);
  return {
    inputTokens: Number.isFinite(inputTokens) ? inputTokens : 0,
    outputTokens: Number.isFinite(outputTokens) ? outputTokens : 0,
    totalTokens: Number.isFinite(totalTokens) ? totalTokens : 0,
    providerCost: cost?.amount ?? null,
    costCurrency: cost?.currency ?? null
  };
}

function providerReportedCost(payload) {
  const preferredKeys = [
    "total_cost_toman",
    "total_cost_usd",
    "total_cost",
    "cost_toman",
    "cost_usd",
    "cost"
  ];
  for (const key of preferredKeys) {
    const cost = findProviderReportedCost(payload, key);
    if (cost) return cost;
  }
  return findProviderReportedCost(payload);
}

function findProviderReportedCost(value, expectedKey) {
  if (Array.isArray(value)) {
    for (const item of value) {
      const cost = findProviderReportedCost(item, expectedKey);
      if (cost) return cost;
    }
    return null;
  }
  if (!value || typeof value !== "object") return null;
  for (const [key, nestedValue] of Object.entries(value)) {
    const normalizedKey = key.toLowerCase();
    const isMatch = expectedKey ? normalizedKey === expectedKey : normalizedKey.includes("cost") || normalizedKey.includes("price");
    if (isMatch) {
      const amount = numericValue(nestedValue);
      if (amount != null) return { amount, currency: currencyName(normalizedKey) };
    }
    const cost = findProviderReportedCost(nestedValue, expectedKey);
    if (cost) return cost;
  }
  return null;
}

function numericValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const number = Number(value.trim());
    return Number.isFinite(number) ? number : null;
  }
  return null;
}

function currencyName(key) {
  if (key.includes("usd")) return "USD";
  if (key.includes("toman")) return "toman";
  if (key.includes("irr") || key.includes("rial")) return "IRR";
  return null;
}

function chatCompletionsUrl(url) {
  const trimmed = String(url || "").trim().replace(/\/+$/, "");
  if (/\/chat\/completions$/i.test(trimmed)) return trimmed;
  if (/\/v1$/i.test(trimmed)) return `${trimmed}/chat/completions`;
  return `${trimmed}/v1/chat/completions`;
}

function safeFileName(value) {
  return value.replace(/[<>:"/\\|?*\x00-\x1f]/g, "-").replace(/\s+/g, " ").trim().slice(0, 120) || "mirook-book";
}

function decodeEntities(text) {
  return text
    .replace(/&nbsp;|&#160;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, number) => String.fromCodePoint(parseInt(number, 10)));
}

function readableText(html) {
  return decodeEntities(
    html
      .replace(/<\s*(head|script|style|svg|math)\b[\s\S]*?<\s*\/\s*\1\s*>/gi, " ")
      .replace(/<\s*br\s*\/?\s*>/gi, "\n")
      .replace(/<\s*\/\s*(p|div|section|article|header|footer|blockquote|li|h[1-6])\s*>/gi, "\n\n")
      .replace(/<[^>]+>/g, " ")
  )
    .replace(/[ \t\f]+/g, " ")
    .replace(/[ \t]*\n[ \t]*/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function appendTextBlocks(text, blocks) {
  text
    .split(/\n\n+/)
    .map((item) => item.trim())
    .filter(Boolean)
    .forEach((item) => blocks.push({ type: "text", text: item }));
}

function parentPath(filePath) {
  const index = filePath.lastIndexOf("/");
  return index >= 0 ? filePath.slice(0, index) : "";
}

function normalizePath(parent, child) {
  const withoutAnchor = decodeURIComponent(child.split("#")[0].split("?")[0].trim());
  const raw = withoutAnchor.startsWith("/")
    ? withoutAnchor.slice(1)
    : [parent, withoutAnchor].filter(Boolean).join("/");
  const parts = [];
  for (const part of raw.split("/")) {
    if (!part || part === ".") continue;
    if (part === "..") parts.pop();
    else parts.push(part);
  }
  return parts.join("/");
}

function mimeType(filePath) {
  const ext = filePath.split(".").pop()?.toLowerCase();
  if (ext === "jpg" || ext === "jpeg") return "image/jpeg";
  if (ext === "gif") return "image/gif";
  if (ext === "webp") return "image/webp";
  if (ext === "svg") return "image/svg+xml";
  return "image/png";
}

function extractAttr(tag, attr) {
  const match = new RegExp(`\\b${attr}\\s*=\\s*["']([^"']*)["']`, "i").exec(tag);
  return match?.[1] ?? "";
}

function resolveEntry(entries, htmlPath, source) {
  const clean = source.split("#")[0].split("?")[0].trim();
  if (!clean) return null;
  const resolved = normalizePath(parentPath(htmlPath), clean);
  if (entries.has(resolved)) return { path: resolved, bytes: entries.get(resolved) };
  const fileName = clean.split("/").pop();
  const fallback = [...entries.entries()].find(([entryPath]) => entryPath.endsWith(`/${fileName}`) || entryPath === fileName);
  return fallback ? { path: fallback[0], bytes: fallback[1] } : null;
}

function parseBlocksFromHtml(htmlPath, html, entries) {
  const images = [];
  const links = [];
  let markedHtml = html;

  [...markedHtml.matchAll(/<a\b[^>]*href\s*=\s*["'][^"']+["'][^>]*>[\s\S]*?<\/a>/gi)]
    .reverse()
    .forEach((match) => {
      const tag = match[0];
      const href = extractAttr(tag, "href");
      const title = readableText(tag);
      const index = links.length;
      links.push({ type: "link", title, href });
      markedHtml = `${markedHtml.slice(0, match.index)}\n\n[[MIROOK_LINK_${index}]]\n\n${markedHtml.slice(match.index + tag.length)}`;
    });

  [...markedHtml.matchAll(/<img\b[^>]*>/gi)]
    .reverse()
    .forEach((match) => {
      const tag = match[0];
      const src = extractAttr(tag, "src");
      const alt = decodeEntities(extractAttr(tag, "alt"));
      const image = resolveEntry(entries, htmlPath, src);
      const index = images.length;
      images.push(
        image
          ? {
              type: "image",
              src: dataUrl(image.bytes, mimeType(image.path)),
              mimeType: mimeType(image.path),
              altText: alt || null
            }
          : null
      );
      markedHtml = `${markedHtml.slice(0, match.index)}\n\n[[MIROOK_IMAGE_${index}]]\n\n${markedHtml.slice(match.index + tag.length)}`;
    });

  const textWithMarkers = readableText(markedHtml);
  const blocks = [];
  const markerRegex = /\[\[MIROOK_(IMAGE|LINK)_(\d+)]]/g;
  let cursor = 0;
  let match;
  while ((match = markerRegex.exec(textWithMarkers))) {
    if (match.index > cursor) appendTextBlocks(textWithMarkers.slice(cursor, match.index), blocks);
    const index = Number(match[2]);
    if (match[1] === "IMAGE" && images[index]) blocks.push(images[index]);
    if (match[1] === "LINK" && links[index]?.title) blocks.push(links[index]);
    cursor = markerRegex.lastIndex;
  }
  if (cursor < textWithMarkers.length) appendTextBlocks(textWithMarkers.slice(cursor), blocks);
  return blocks;
}

async function parseEpub(epubBytes) {
  const zip = await JSZip.loadAsync(Buffer.from(epubBytes));
  const entries = new Map();
  await Promise.all(
    Object.values(zip.files).map(async (entry) => {
      if (!entry.dir) entries.set(entry.name, await entry.async("uint8array"));
    })
  );

  const opfEntry = [...entries.entries()].find(([entryPath]) => entryPath.toLowerCase().endsWith(".opf"));
  const htmlPaths = orderedHtmlPaths(entries, opfEntry);
  const pages = [];
  for (const htmlPath of htmlPaths) {
    const html = bytesToString(entries.get(htmlPath));
    pages.push({
      index: pages.length,
      title: null,
      blocks: parseBlocksFromHtml(htmlPath, html, entries)
    });
  }
  return pages;
}

function orderedHtmlPaths(entries, opfEntry) {
  const allHtml = [...entries.keys()]
    .filter((entryPath) => /\.(xhtml|html|htm)$/i.test(entryPath))
    .filter((entryPath) => !/(^|\/)(nav|toc)\./i.test(entryPath))
    .sort();

  if (!opfEntry) return allHtml;
  const [opfPath, opfBytes] = opfEntry;
  const opf = bytesToString(opfBytes);
  const opfBase = parentPath(opfPath);
  const manifest = new Map();
  for (const match of opf.matchAll(/<item\b[^>]*>/gi)) {
    const tag = match[0];
    const id = extractAttr(tag, "id");
    const href = extractAttr(tag, "href");
    if (id && href) manifest.set(id, normalizePath(opfBase, href));
  }
  const ordered = [];
  for (const match of opf.matchAll(/<itemref\b[^>]*>/gi)) {
    const idref = extractAttr(match[0], "idref");
    const entryPath = manifest.get(idref);
    if (entryPath && allHtml.includes(entryPath)) ordered.push(entryPath);
  }
  const remaining = allHtml.filter((entryPath) => !ordered.includes(entryPath));
  return ordered.length ? [...ordered, ...remaining] : allHtml;
}

async function readMirookBook(filePath) {
  const SQL = await getSql();
  const fileBytes = fs.readFileSync(filePath);
  const fingerprint = crypto.createHash("sha256").update(fileBytes).digest("hex");
  const db = new SQL.Database(fileBytes);
  try {
    const encryption = oneValue(db, "SELECT value FROM book_info WHERE key = $key LIMIT 1", { $key: "encryption" });
    if (encryption) {
      throw new Error("Password protected MRBK files are not supported in this first Electron reader step.");
    }

    const manifestRaw = oneValue(db, "SELECT json FROM metadata WHERE key = $key LIMIT 1", { $key: "manifest" });
    if (!manifestRaw) throw new Error("MRBK manifest was not found.");
    const manifest = JSON.parse(bytesToString(manifestRaw));
    const sourceKind = String(manifest.sourceKind || "pdf").toLowerCase();
    const sourceKey = sourceKind === "epub" ? "sourceEPUB" : "sourcePDF";
    const sourceBytes = normalizeBytes(oneValue(db, "SELECT json FROM metadata WHERE key = $key LIMIT 1", { $key: sourceKey }));

    const pages = allRows(db, "SELECT page_index AS pageIndex, json FROM pages ORDER BY page_index ASC").map((row) => ({
      pageIndex: Number(row.pageIndex),
      ...JSON.parse(bytesToString(row.json))
    }));

    const epubPages = sourceKind === "epub" && sourceBytes ? await parseEpub(sourceBytes) : [];
    const sourcePdf = sourceKind === "pdf" && sourceBytes ? dataUrl(sourceBytes, "application/pdf") : null;
    const payload = {
      filePath,
      id: fingerprint,
      fingerprint,
      manifest,
      pages,
      epubPages,
      sourcePdf
    };
    await upsertBookRecord(payload);
    payload.readerState = await readerStateForBook(payload.id);
    return payload;
  } finally {
    db.close();
  }
}

ipcMain.handle("book:open", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: "Open MRBK",
    properties: ["openFile"],
    filters: [{ name: "Mirook Book", extensions: ["mrbk"] }]
  });
  if (result.canceled || !result.filePaths[0]) return null;
  return readMirookBook(result.filePaths[0]);
});

ipcMain.handle("book:openPath", async (_event, filePath) => {
  if (!filePath || path.extname(filePath).toLowerCase() !== ".mrbk") {
    throw new Error("Please drop a .mrbk file.");
  }
  return readMirookBook(filePath);
});

ipcMain.handle("window:toggleZoom", () => {
  if (!mainWindow) return false;
  if (mainWindow.isMaximized()) {
    mainWindow.unmaximize();
    return false;
  }
  mainWindow.maximize();
  return true;
});

ipcMain.handle("reader:savePosition", async (_event, position) => {
  if (!position?.bookId) return false;
  const db = await getReaderDb();
  run(
    db,
    `INSERT INTO reading_positions (book_id, page_index, view_mode, font_size, scroll_original, scroll_translation, updated_at)
     VALUES ($bookId, $pageIndex, $viewMode, $fontSize, $scrollOriginal, $scrollTranslation, $updatedAt)
     ON CONFLICT(book_id) DO UPDATE SET
       page_index = excluded.page_index,
       view_mode = excluded.view_mode,
       font_size = excluded.font_size,
       scroll_original = excluded.scroll_original,
       scroll_translation = excluded.scroll_translation,
       updated_at = excluded.updated_at`,
    {
      $bookId: position.bookId,
      $pageIndex: Number(position.pageIndex || 0),
      $viewMode: String(position.viewMode || "split"),
      $fontSize: position.fontSize == null ? null : Number(position.fontSize),
      $scrollOriginal: Number(position.scrollOriginal || 0),
      $scrollTranslation: Number(position.scrollTranslation || 0),
      $updatedAt: new Date().toISOString()
    }
  );
  saveReaderDb();
  return true;
});

ipcMain.handle("reader:exportBookData", async (_event, bookId) => exportBookData(bookId));
ipcMain.handle("reader:saveAnnotation", async (_event, annotation) => saveAnnotation(annotation));
ipcMain.handle("reader:deleteAnnotation", async (_event, id) => deleteAnnotation(id));
ipcMain.handle("reader:summarizePages", async (_event, request) => summarizePages(request));
ipcMain.handle("reader:generateTextFromNotes", async (_event, request) => generateTextFromNotes(request));
ipcMain.handle("reader:deleteAiOutput", async (_event, id) => deleteAiOutput(id));
ipcMain.handle("settings:getAi", async () => getAiSettings());
ipcMain.handle("settings:saveAi", async (_event, settings) => saveAiSettings(settings));

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
