const { app, BrowserWindow, dialog, ipcMain } = require("electron");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const JSZip = require("jszip");
const initSqlJs = require("sql.js");

let mainWindow;
let sqlPromise;

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
  const db = new SQL.Database(fs.readFileSync(filePath));
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
    return {
      filePath,
      id: crypto.createHash("sha1").update(filePath).digest("hex"),
      manifest,
      pages,
      epubPages,
      sourcePdf
    };
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

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
