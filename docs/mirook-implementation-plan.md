# Mirook — Implementation Plan

## 1. Technical Stack

### Platform

- macOS native app
- Swift
- SwiftUI
- AppKit where needed
- PDFKit
- Core Graphics
- Vision framework as an optional OCR fallback

### AI Provider

- OpenAI API
- Vision-capable model for page image understanding
- Structured JSON output for text blocks and translations

### Local Storage

- UserDefaults for simple preferences
- Keychain for OpenAI API key
- Local file system for imported PDFs and generated exports

## 2. High-Level Architecture

```text
PDF Document
    ↓
PDFKit Reader
    ↓
Selected Page Renderer
    ↓
Page Image sent to OpenAI
    ↓
Structured Translation JSON
    ↓
Layout Reconstruction Engine
    ↓
Translated PDF Page
    ↓
Merged Export PDF
```

## 3. Main App Modules

### 3.1 App Shell

Responsible for the main macOS app structure.

Components:

- `MirookApp`
- `MainWindowView`
- `SidebarView`
- `ReaderView`
- `TranslationInspectorView`

Tasks:

- Create the main app window.
- Implement a clean three-column layout.
- Support opening PDF files.
- Manage selected document state.

---

### 3.2 PDF Reader Module

Responsible for loading, displaying, and navigating PDF documents.

Suggested files:

- `PDFDocumentStore.swift`
- `PDFKitView.swift`
- `PDFPageSelection.swift`

Responsibilities:

- Load PDF from file URL.
- Display PDF using `PDFView` inside SwiftUI.
- Track current page.
- Support zoom.
- Support page range selection.

MVP tasks:

- Open PDF.
- Show PDF.
- Navigate pages.
- Get current page index.
- Get selected page range.

---

### 3.3 Page Rendering Module

Responsible for converting a PDF page into an image that can be sent to OpenAI.

Suggested files:

- `PDFPageRenderer.swift`
- `RenderedPage.swift`

Responsibilities:

- Render selected PDF page to PNG or JPEG.
- Control render scale.
- Preserve page aspect ratio.
- Store rendered page dimensions.

Suggested output model:

```swift
struct RenderedPage {
    let pageIndex: Int
    let imageData: Data
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
}
```

MVP recommendation:

- Render pages at 2x scale for better OCR and layout understanding.
- Compress image reasonably before sending to OpenAI.

---

### 3.4 OpenAI Client Module

Responsible for calling OpenAI and receiving structured translation data.

Suggested files:

- `OpenAIClient.swift`
- `TranslationRequestBuilder.swift`
- `TranslationResponseParser.swift`

Responsibilities:

- Read API key from Keychain.
- Build a Responses API request with text and image input.
- Send page image and translation instructions.
- Enforce Structured Outputs with a JSON Schema.
- Decode translated blocks.
- Handle refusals, invalid output, network errors, rate limits, and retries.

API recommendation:

- Use the OpenAI Responses API for the MVP because it supports image input and structured text/JSON output in one request.
- Store the model name as a setting instead of hard-coding it.
- Default to the current recommended vision-capable OpenAI model at implementation time.
- Keep the request builder isolated so model names, response format details, and prompt wording can change without touching the renderer.

Suggested response model:

```swift
struct TranslatedPage: Codable {
    let pageWidth: Double
    let pageHeight: Double
    let blocks: [TranslatedTextBlock]
}

struct TranslatedTextBlock: Codable, Identifiable {
    let id: String
    let sourceText: String
    let translatedText: String
    let bbox: BoundingBox
    let role: TextRole
    let confidence: Double?
}

struct BoundingBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum TextRole: String, Codable {
    case title
    case heading
    case paragraph
    case footnote
    case caption
    case pageNumber
    case other
}
```

Suggested OpenAI instruction:

```text
You are translating a PDF page into fluent Persian.
Analyze the full page image.
Detect readable text blocks.
Translate only normal readable text.
Do not translate images, charts, diagrams, logos, or decorative elements.
Return JSON only.
For each text block, return source_text, translated_text, bbox, role, and confidence.
Bounding boxes must use image coordinates.
Preserve paragraph meaning, names, numbers, punctuation, and tone.
```

Suggested structured output schema:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["page_width", "page_height", "blocks"],
  "properties": {
    "page_width": { "type": "number" },
    "page_height": { "type": "number" },
    "blocks": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "source_text", "translated_text", "bbox", "role", "confidence"],
        "properties": {
          "id": { "type": "string" },
          "source_text": { "type": "string" },
          "translated_text": { "type": "string" },
          "bbox": {
            "type": "object",
            "additionalProperties": false,
            "required": ["x", "y", "width", "height"],
            "properties": {
              "x": { "type": "number" },
              "y": { "type": "number" },
              "width": { "type": "number" },
              "height": { "type": "number" }
            }
          },
          "role": {
            "type": "string",
            "enum": ["title", "heading", "paragraph", "footnote", "caption", "pageNumber", "other"]
          },
          "confidence": {
            "type": "number",
            "minimum": 0,
            "maximum": 1
          }
        }
      }
    }
  }
}
```

---

### 3.5 Layout Reconstruction Module

Responsible for creating a translated visual page.

Suggested files:

- `TranslatedPageRenderer.swift`
- `PersianTextLayoutEngine.swift`
- `PDFExportRenderer.swift`

Responsibilities:

- Use the original rendered page as the background.
- Cover original text areas with white or sampled background patches.
- Draw translated Persian text inside the returned bounding boxes.
- Support right-to-left text layout.
- Adjust font size to fit boxes.
- Export rendered result as PDF page.

MVP rendering approach:

1. Render the original page as background.
2. For each translated block:
   - Draw a white rectangle over the original text box.
   - Add translated Persian text in the same area.
   - Use a readable Persian-compatible font.
   - Reduce font size if the text does not fit.
3. Save the output as a new PDF page.

Recommended Persian fonts:

- Vazirmatn
- IRANSansX if licensed
- Noto Sans Arabic
- System fallback Arabic/Persian font

---

### 3.6 Export Module

Responsible for generating the final continuous PDF.

Suggested files:

- `PDFBookExporter.swift`
- `ExportOptions.swift`

Responsibilities:

- Collect translated pages.
- Preserve page order.
- Merge pages into a single PDF.
- Save file to user-selected location.

MVP export options:

- Export selected pages only.
- Export translated pages as one continuous PDF.
- File name pattern: `OriginalName - Mirook Translation.pdf`

---

### 3.7 Settings Module

Responsible for user preferences and API configuration.

Suggested files:

- `SettingsView.swift`
- `KeychainService.swift`
- `AppPreferences.swift`

Settings:

- OpenAI API key
- Default target language
- Default model
- Default export location
- Layout mode
- Translation quality mode

MVP settings:

- API key
- Target language
- Model name

## 4. Development Phases

Current progress:

- [x] Xcode project generated with XcodeGen.
- [x] macOS SwiftUI app builds successfully.
- [x] PDF opening and native PDF viewing are implemented.
- [x] Basic page navigation and zoom controls are implemented.
- [x] Page rendering pipeline is implemented for the current page.
- [ ] OpenAI translation pipeline has not started yet.

### Phase 1 — Project Setup

Goal: Create a working macOS shell app.

Tasks:

- [x] Create Xcode macOS SwiftUI project.
- [x] Add basic sidebar and main reader area.
- [x] Add a simple app icon placeholder.
- [x] Add settings window placeholder.
- [x] Add file picker for opening PDFs.

Deliverable:

- [x] User can open the app and choose a PDF file.

---

### Phase 2 — PDF Reader

Goal: Display PDFs natively.

Tasks:

- [x] Integrate PDFKit with SwiftUI using `NSViewRepresentable`.
- [x] Load selected PDF into `PDFView`.
- [x] Add page navigation.
- [x] Add zoom controls.
- [x] Track current page.

Deliverable:

- [x] User can open and read a PDF inside Mirook.

---

### Phase 3 — Page Rendering

Goal: Convert selected PDF pages to images.

Tasks:

- [x] Implement `PDFPageRenderer`.
- [x] Render current page to PNG.
- [x] Store page dimensions.
- [x] Preview rendered page for debugging.

Deliverable:

- [x] App can render any selected PDF page as an image.

---

### Phase 4 — OpenAI Translation Pipeline

Goal: Send a full page image to OpenAI and receive structured translation data.

Tasks:

- [ ] Add API key storage in Keychain.
- [ ] Implement `OpenAIClient`.
- [ ] Build a Responses API request with image input.
- [ ] Create structured JSON prompt.
- [ ] Define and attach the translation JSON Schema.
- [ ] Parse response into Swift models.
- [ ] Handle Structured Output refusals and invalid responses.
- [ ] Add retry behavior for transient network and rate-limit errors.
- [ ] Display detected translated blocks in a debug panel.

Deliverable:

- [ ] App can send one PDF page to OpenAI and receive Persian translated blocks with bounding boxes.

---

### Phase 5 — Translated Page Rendering

Goal: Generate a visual translated page.

Tasks:

- [ ] Use original page image as background.
- [ ] Overlay translated Persian text blocks.
- [ ] Implement right-to-left text drawing.
- [ ] Fit text into bounding boxes.
- [ ] Hide original English text areas.
- [ ] Generate a translated page preview.

Deliverable:

- [ ] User can see a translated page that resembles the original page.

---

### Phase 6 — PDF Export

Goal: Export translated pages as a PDF.

Tasks:

- [ ] Convert translated page renderings into PDF pages.
- [ ] Merge multiple pages.
- [ ] Add save panel.
- [ ] Export final PDF.

Deliverable:

- [ ] User can export selected translated pages as one continuous PDF.

---

### Phase 7 — UX Polish

Goal: Make the app feel clean and stable.

Tasks:

- [ ] Add progress states.
- [x] Add error messages.
- [ ] Add cancel translation button.
- [ ] Add recent files.
- [x] Improve empty states.
- [ ] Improve page range selection.
- [x] Add basic settings.

Deliverable:

- [ ] MVP feels usable as a personal macOS utility.

## 5. Suggested MVP Timeline

### Week 1

- Project setup
- PDF opening
- PDF reading
- Page rendering

### Week 2

- OpenAI API integration
- Structured JSON translation response
- Debug translation viewer

### Week 3

- Layout reconstruction
- Persian text overlay
- Single-page export

### Week 4

- Multi-page translation
- PDF merging
- Settings
- UX polish

## 6. Technical Challenges and Solutions

### Challenge: Persian Text Does Not Fit Original Boxes

Possible solutions:

- Auto-reduce font size.
- Increase line count inside the same box.
- Allow slight box expansion when safe.
- Add a fallback reflow mode later.

### Challenge: OpenAI Bounding Boxes Are Not Perfect

Possible solutions:

- Use OpenAI boxes for MVP.
- Later combine with Apple Vision OCR boxes.
- Add manual correction UI in future versions.

### Challenge: Complex Backgrounds Behind Text

Possible solutions:

- Use white rectangles for MVP.
- Later sample local background color.
- Later use image inpainting or background reconstruction.

### Challenge: Tables and Diagrams

Possible solutions:

- Skip translating chart labels in MVP.
- Treat table cells as separate blocks later.
- Add table-aware translation mode later.

### Challenge: API Cost

Possible solutions:

- Translate selected pages only.
- Add quality modes.
- Cache translated pages.
- Avoid re-translating the same page.

## 7. Recommended JSON Contract

Coordinate assumptions:

- Bounding boxes use rendered image coordinates.
- Origin is top-left.
- `page_width` and `page_height` must match the rendered image size sent to the model.

```json
{
  "page_width": 1654,
  "page_height": 2339,
  "blocks": [
    {
      "id": "block_001",
      "source_text": "The Five Competitive Forces",
      "translated_text": "پنج نیروی رقابتی",
      "bbox": {
        "x": 320,
        "y": 280,
        "width": 740,
        "height": 160
      },
      "role": "title",
      "confidence": 0.94
    }
  ]
}
```

Swift decoding note:

- The JSON contract uses `snake_case`.
- The Swift models use `camelCase`.
- Use `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` or explicit `CodingKeys`.

## 8. Recommended First Prototype Milestone

The first prototype should only do this:

1. Open one PDF.
2. Render the current page as an image.
3. Send the image to OpenAI.
4. Receive translated blocks.
5. Draw the Persian translations on top of the page.
6. Export that one page as PDF.

This keeps the first milestone small but proves the hardest technical part of the product.

## 9. Future Improvements

- Manual text block editing.
- Glossary support.
- Translation memory.
- Side-by-side original and translated reading mode.
- Batch translation queue.
- Local OCR fallback.
- Better table support.
- Better typography matching.
- Export to EPUB.
- Export to Markdown.
- Multi-language translation presets.

## 10. Final Recommendation

Build the MVP around a single-page translation pipeline first. Do not start with whole-book translation. Once one page can be translated, reconstructed, previewed, and exported reliably, the same pipeline can be scaled to page ranges and eventually full books.

The hardest part of Mirook is not PDF viewing or OpenAI translation. The hardest part is layout reconstruction. The implementation plan should therefore prove the layout pipeline as early as possible.
