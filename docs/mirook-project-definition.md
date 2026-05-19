# Mirook — Project Definition

## 1. Product Summary

**Mirook** is a native macOS application for translating PDF pages while preserving the original visual structure of the document. The user can open a PDF, read it inside the app, select one or more pages, translate them using OpenAI, and export the translated pages as a continuous PDF book.

The core idea is simple: **mirror every page into the user’s language without damaging the original layout**.

## 2. Product Vision

Mirook aims to become a clean, focused, macOS-native reading and translation tool for books, reports, academic papers, manuals, and long-form PDFs. Instead of producing plain translated text, Mirook should generate a translated version of each page that visually resembles the source page.

Images, charts, diagrams, tables, and visual elements should remain untouched unless they contain normal readable text that the user explicitly wants to translate.

## 3. Target Users

- Readers who consume English PDFs but prefer reading in Persian or another language.
- Students and researchers reading academic books, papers, and technical documents.
- Professionals who need translated reports while keeping the original page layout.
- Personal users who want a private desktop-first PDF translation workflow.

## 4. Core Use Case

1. User opens a PDF in Mirook.
2. User reads the PDF inside a native macOS viewer.
3. User selects a page or page range.
4. User clicks **Translate**.
5. Mirook sends the full rendered page image to an OpenAI vision-capable model.
6. The model detects text blocks and returns translated Persian text with bounding boxes.
7. Mirook reconstructs the page using the original page background and translated text overlays.
8. User exports translated pages as a single continuous PDF.

## 5. MVP Scope

The first version should focus on translating selected PDF pages with acceptable layout preservation.

### MVP Features

- Native macOS app built with SwiftUI and PDFKit.
- Open PDF file.
- Display PDF pages inside the app.
- Select current page or page range.
- Render selected PDF page as an image.
- Send page image to OpenAI for text detection and translation.
- Receive structured JSON response containing translated text blocks and approximate bounding boxes.
- Generate a translated PDF page by placing Persian text over the original page background.
- Export selected translated pages as a merged PDF.
- Store OpenAI API key locally for personal use.

## 6. Non-MVP Features

These should be postponed until the core workflow works reliably.

- Batch translation of very large books.
- Advanced OCR fallback for scanned pages.
- Custom translation memory.
- Glossary and terminology management.
- Multi-language UI.
- Cloud sync.
- Team collaboration.
- App Store distribution.
- Fully automated perfect layout reconstruction.

## 7. Key Product Principles

### Preserve the Page

The translated page should feel like a mirrored version of the original page. The user should recognize the same layout, spacing, images, diagrams, and visual hierarchy.

### Keep Images Untouched

Images, charts, illustrations, and diagrams should remain visually unchanged. Only normal readable text should be translated.

### Native macOS Feel

The app should feel like a polished macOS utility: minimal, fast, calm, and document-focused.

### User Control

The user should choose whether to translate one page, a range of pages, or eventually the whole document.

### Personal-First

The first version is designed as a personal desktop app, so API-key storage can be simple, preferably using macOS Keychain.

## 10. Main Screens

### Library Screen

A simple document library with recent PDFs and an Open PDF button.

### Reader Screen

A PDF reading interface with page navigation, zoom controls, and translation actions.

### Translation Panel

A side panel containing:

- Source language
- Target language
- Translation quality mode
- Layout mode
- Page range
- Translate button

### Export Screen

A simple export flow for saving translated pages as a continuous PDF.

## 11. Translation Modes

### Mirror Layout

The app attempts to preserve the original page layout by overlaying translated text into matching regions.

### Text-Only Reflow

The app extracts translated text into a clean reading format without trying to match the original page layout. This can be added later as a fallback mode.

## 12. Technical Assumptions

- The app is native macOS.
- The app uses SwiftUI for UI and PDFKit for PDF display.
- Each page can be rendered into an image before being sent to OpenAI.
- OpenAI returns structured JSON with translated blocks and bounding boxes.
- The first version prioritizes good-enough layout preservation over pixel-perfect reconstruction.
- Persian text rendering requires proper right-to-left handling.

## 13. Major Risks

### Layout Accuracy

Maintaining the original layout after translation is difficult because Persian text length differs from English text.

### Bounding Box Precision

OpenAI may return approximate coordinates. Additional layout correction may be required.

### Cost and Latency

Sending full-page images to OpenAI can be slower and more expensive than sending plain text.

### Font Matching

The translated text may not perfectly match the visual style of the original page.

### Complex Pages

Dense academic pages, tables, multi-column layouts, footnotes, and charts may require special handling.

## 14. Definition of Success for MVP

The MVP is successful if a user can:

1. Open a PDF.
2. Select a page.
3. Translate it to Persian using OpenAI.
4. See a translated page that resembles the original page.
5. Export the translated result as a PDF.

The output does not need to be perfect, but it should be readable, visually organized, and clearly useful.
