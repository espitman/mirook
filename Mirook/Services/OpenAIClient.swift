import Foundation

enum OpenAIClientError: LocalizedError {
    case missingAPIKey
    case invalidRequestBody
    case invalidResponse
    case apiError(String)
    case refusal(String)
    case missingOutputText
    case invalidTranslationJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenAI API key in Settings before translating."
        case .invalidRequestBody:
            "Mirook could not build the OpenAI request."
        case .invalidResponse:
            "OpenAI returned an invalid response."
        case .apiError(let message):
            message
        case .refusal(let message):
            "OpenAI refused the request: \(message)"
        case .missingOutputText:
            "OpenAI did not return translated page JSON."
        case .invalidTranslationJSON:
            "Mirook could not decode the translated page JSON."
        }
    }
}

struct OpenAIClient {
    private let apiKey: String
    private let urlSession: URLSession

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func translatePage(
        renderedPage: RenderedPage,
        targetLanguage: String,
        model: String
    ) async throws -> TranslatedPage {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        let body = try makeRequestBody(renderedPage: renderedPage, targetLanguage: targetLanguage, model: model)

        var lastRetryableError: Error?
        for attempt in 1...3 {
            do {
                return try await performTranslationRequest(body: body)
            } catch let error as RetryableOpenAIError {
                lastRetryableError = error
                if attempt == 3 {
                    break
                }
                try await Task.sleep(for: .seconds(attempt))
            } catch let error as URLError {
                lastRetryableError = error
                if attempt == 3 {
                    break
                }
                try await Task.sleep(for: .seconds(attempt))
            }
        }

        if let retryableError = lastRetryableError {
            throw OpenAIClientError.apiError(retryableError.localizedDescription)
        }

        throw OpenAIClientError.invalidResponse
    }

    private func performTranslationRequest(body: Data) async throws -> TranslatedPage {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "OpenAI returned HTTP \(httpResponse.statusCode)."
            if httpResponse.statusCode == 429 || (500..<600).contains(httpResponse.statusCode) {
                throw RetryableOpenAIError.httpStatus(httpResponse.statusCode, message)
            }
            throw OpenAIClientError.apiError(message)
        }

        let responsePayload = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let refusal = responsePayload.refusalText {
            throw OpenAIClientError.refusal(refusal)
        }

        guard let outputText = responsePayload.outputText else {
            throw OpenAIClientError.missingOutputText
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let jsonData = outputText.data(using: .utf8),
              let translatedPage = try? decoder.decode(TranslatedPage.self, from: jsonData) else {
            throw OpenAIClientError.invalidTranslationJSON
        }

        return translatedPage
    }

    private func makeRequestBody(
        renderedPage: RenderedPage,
        targetLanguage: String,
        model: String
    ) throws -> Data {
        let imageBase64 = renderedPage.imageData.base64EncodedString()
        let prompt = """
        You are translating a PDF page into fluent \(targetLanguage).
        Analyze the full page image.
        Detect readable text blocks.
        Translate only normal readable text.
        Do not translate images, charts, diagrams, logos, decorative elements, or non-text visual content.
        Return JSON that matches the provided schema.
        Bounding boxes must use the rendered image coordinate system.
        The coordinate origin is top-left.
        The page_width and page_height fields must exactly match \(Int(renderedPage.width)) and \(Int(renderedPage.height)).
        Preserve paragraph meaning, names, numbers, punctuation, and tone.
        """

        let body: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": prompt
                        ],
                        [
                            "type": "input_image",
                            "image_url": "data:image/png;base64,\(imageBase64)",
                            "detail": "high"
                        ]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "translated_page",
                    "strict": true,
                    "schema": Self.makeTranslationSchema()
                ]
            ]
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenAIClientError.invalidRequestBody
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func makeTranslationSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["page_width", "page_height", "blocks"],
            "properties": [
                "page_width": ["type": "number"],
                "page_height": ["type": "number"],
                "blocks": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["id", "source_text", "translated_text", "bbox", "role", "confidence"],
                        "properties": [
                            "id": ["type": "string"],
                            "source_text": ["type": "string"],
                            "translated_text": ["type": "string"],
                            "bbox": [
                                "type": "object",
                                "additionalProperties": false,
                                "required": ["x", "y", "width", "height"],
                                "properties": [
                                    "x": ["type": "number"],
                                    "y": ["type": "number"],
                                    "width": ["type": "number"],
                                    "height": ["type": "number"]
                                ]
                            ],
                            "role": [
                                "type": "string",
                                "enum": TextRole.allCases.map(\.rawValue)
                            ],
                            "confidence": [
                                "type": "number",
                                "minimum": 0,
                                "maximum": 1
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }
}

private enum RetryableOpenAIError: LocalizedError {
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode, let message):
            "OpenAI returned retryable HTTP \(statusCode): \(message)"
        }
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}

private struct OpenAIResponse: Decodable {
    let output: [OutputItem]

    var outputText: String? {
        output.compactMap { item in
            item.content?.compactMap { content in
                content.type == "output_text" ? content.text : nil
            }.joined()
        }
        .first { !$0.isEmpty }
    }

    var refusalText: String? {
        output.compactMap { item in
            item.content?.compactMap { content in
                content.type == "refusal" ? content.refusal : nil
            }.joined()
        }
        .first { !$0.isEmpty }
    }

    struct OutputItem: Decodable {
        let content: [ContentItem]?
    }

    struct ContentItem: Decodable {
        let type: String
        let text: String?
        let refusal: String?
    }
}
