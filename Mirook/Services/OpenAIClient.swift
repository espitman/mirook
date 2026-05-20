import Foundation

enum OpenAIClientError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case invalidRequestBody
    case invalidResponse
    case apiError(String)
    case refusal(String)
    case missingOutputText
    case invalidTranslationJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your AI provider API key in Settings before translating."
        case .invalidBaseURL:
            "The AI provider base URL is invalid."
        case .invalidRequestBody:
            "Mirook could not build the AI request."
        case .invalidResponse:
            "The AI provider returned an invalid response."
        case .apiError(let message):
            message
        case .refusal(let message):
            "The AI provider refused the request: \(message)"
        case .missingOutputText:
            "The AI provider did not return translated page JSON."
        case .invalidTranslationJSON:
            "Mirook could not decode the translated page JSON."
        }
    }
}

struct OpenAIClient {
    enum APIStyle: String {
        case responses
        case chatCompletions
    }

    private let apiKey: String
    private let baseURL: String
    private let apiStyle: APIStyle
    private let urlSession: URLSession

    init(
        apiKey: String,
        baseURL: String = "https://api.openai.com/v1",
        apiStyle: APIStyle = .responses,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.apiStyle = apiStyle
        self.urlSession = urlSession
    }

    func translatePage(
        renderedPage: RenderedPage,
        targetLanguage: String,
        model: String
    ) async throws -> AIPageTranslationResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        let request = try makeRequest(renderedPage: renderedPage, targetLanguage: targetLanguage, model: model)

        var lastRetryableError: Error?
        for attempt in 1...3 {
            do {
                return try await performTranslationRequest(request: request)
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

    func translateText(
        _ text: String,
        targetLanguage: String,
        model: String
    ) async throws -> AITextTranslationResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw OpenAIClientError.missingOutputText
        }

        let request = try makeTextTranslationRequest(
            text: trimmedText,
            targetLanguage: targetLanguage,
            model: model
        )

        var lastRetryableError: Error?
        for attempt in 1...3 {
            do {
                return try await performTextRequest(request: request)
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

    func listModels() async throws -> [AIModelInfo] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        guard let url = endpointURL(path: "/models") else {
            throw OpenAIClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "AI provider returned HTTP \(httpResponse.statusCode)."
            throw OpenAIClientError.apiError(message)
        }

        let responsePayload = try JSONDecoder().decode(ModelListResponse.self, from: data)
        let uniqueIDs = Set(responsePayload.data.map(\.id))
        return uniqueIDs
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { AIModelInfo(id: $0) }
    }

    private func performTranslationRequest(request: URLRequest) async throws -> AIPageTranslationResult {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "AI provider returned HTTP \(httpResponse.statusCode)."
            if httpResponse.statusCode == 429 || (500..<600).contains(httpResponse.statusCode) {
                throw RetryableOpenAIError.httpStatus(httpResponse.statusCode, message)
            }
            throw OpenAIClientError.apiError(message)
        }

        let output = try outputResult(from: data)
        guard let outputText = output.text else {
            throw OpenAIClientError.missingOutputText
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let jsonData = outputText.data(using: .utf8),
              let translatedPage = try? decoder.decode(TranslatedPage.self, from: jsonData) else {
            throw OpenAIClientError.invalidTranslationJSON
        }

        return AIPageTranslationResult(page: translatedPage, usage: output.usage)
    }

    private func performTextRequest(request: URLRequest) async throws -> AITextTranslationResult {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "AI provider returned HTTP \(httpResponse.statusCode)."
            if httpResponse.statusCode == 429 || (500..<600).contains(httpResponse.statusCode) {
                throw RetryableOpenAIError.httpStatus(httpResponse.statusCode, message)
            }
            throw OpenAIClientError.apiError(message)
        }

        let output = try outputResult(from: data)
        guard let outputText = output.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !outputText.isEmpty else {
            throw OpenAIClientError.missingOutputText
        }

        return AITextTranslationResult(text: outputText, usage: output.usage)
    }

    private func makeRequest(
        renderedPage: RenderedPage,
        targetLanguage: String,
        model: String
    ) throws -> URLRequest {
        let endpoint = switch apiStyle {
        case .responses:
            "/responses"
        case .chatCompletions:
            "/chat/completions"
        }

        guard let url = endpointURL(path: endpoint) else {
            throw OpenAIClientError.invalidBaseURL
        }

        let body = switch apiStyle {
        case .responses:
            try makeResponsesRequestBody(renderedPage: renderedPage, targetLanguage: targetLanguage, model: model)
        case .chatCompletions:
            try makeChatCompletionsRequestBody(renderedPage: renderedPage, targetLanguage: targetLanguage, model: model)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func makeTextTranslationRequest(
        text: String,
        targetLanguage: String,
        model: String
    ) throws -> URLRequest {
        let endpoint = switch apiStyle {
        case .responses:
            "/responses"
        case .chatCompletions:
            "/chat/completions"
        }

        guard let url = endpointURL(path: endpoint) else {
            throw OpenAIClientError.invalidBaseURL
        }

        let body = switch apiStyle {
        case .responses:
            try makeTextResponsesRequestBody(text: text, targetLanguage: targetLanguage, model: model)
        case .chatCompletions:
            try makeTextChatCompletionsRequestBody(text: text, targetLanguage: targetLanguage, model: model)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func makeResponsesRequestBody(
        renderedPage: RenderedPage,
        targetLanguage: String,
        model: String
    ) throws -> Data {
        let imageBase64 = renderedPage.imageData.base64EncodedString()
        let prompt = translationPrompt(renderedPage: renderedPage, targetLanguage: targetLanguage)
        let systemPrompt = translationSystemPrompt(targetLanguage: targetLanguage)

        let body: [String: Any] = [
            "model": model,
            "instructions": systemPrompt,
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

    private func makeChatCompletionsRequestBody(
        renderedPage: RenderedPage,
        targetLanguage: String,
        model: String
    ) throws -> Data {
        let imageBase64 = renderedPage.imageData.base64EncodedString()
        let prompt = """
        \(translationPrompt(renderedPage: renderedPage, targetLanguage: targetLanguage))

        Return only valid JSON. Do not wrap it in Markdown.

        JSON shape:
        {
          "page_width": \(Int(renderedPage.width)),
          "page_height": \(Int(renderedPage.height)),
          "blocks": [
            {
              "id": "block_001",
              "source_text": "original text",
              "translated_text": "translated text",
              "bbox": { "x": 0, "y": 0, "width": 100, "height": 40 },
              "role": "paragraph",
              "confidence": 0.9
            }
          ]
        }

        Valid role values: \(TextRole.allCases.map(\.rawValue).joined(separator: ", ")).
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": translationSystemPrompt(targetLanguage: targetLanguage)
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(imageBase64)",
                                "detail": "high"
                            ]
                        ]
                    ]
                ]
            ],
            "response_format": [
                "type": "json_object"
            ],
            "temperature": 0
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenAIClientError.invalidRequestBody
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    private func translationPrompt(renderedPage: RenderedPage, targetLanguage: String) -> String {
        """
        You are translating a PDF page into fluent \(targetLanguage).
        Analyze the full page image.
        Detect readable text blocks.
        Translate only normal readable text.
        \(languageStyleInstruction(targetLanguage: targetLanguage))
        Do not translate images, charts, diagrams, logos, decorative elements, or non-text visual content.
        Return JSON that matches the expected translation contract.
        Bounding boxes must use the rendered image coordinate system.
        The coordinate origin is top-left.
        The page_width and page_height fields must exactly match \(Int(renderedPage.width)) and \(Int(renderedPage.height)).
        Preserve paragraph meaning, names, numbers, punctuation, and tone.
        """
    }

    private func makeTextResponsesRequestBody(
        text: String,
        targetLanguage: String,
        model: String
    ) throws -> Data {
        let systemPrompt = translationSystemPrompt(targetLanguage: targetLanguage)
        let body: [String: Any] = [
            "model": model,
            "instructions": systemPrompt,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": textTranslationPrompt(text: text, targetLanguage: targetLanguage)
                        ]
                    ]
                ]
            ]
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenAIClientError.invalidRequestBody
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    private func makeTextChatCompletionsRequestBody(
        text: String,
        targetLanguage: String,
        model: String
    ) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": translationSystemPrompt(targetLanguage: targetLanguage)
                ],
                [
                    "role": "user",
                    "content": textTranslationPrompt(text: text, targetLanguage: targetLanguage)
                ]
            ],
            "temperature": 0
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenAIClientError.invalidRequestBody
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    private func textTranslationPrompt(text: String, targetLanguage: String) -> String {
        """
        Translate the following book page into fluent \(targetLanguage).
        \(languageStyleInstruction(targetLanguage: targetLanguage))
        Preserve paragraph breaks, headings, names, numbers, references, and tone.
        Do not summarize.
        Return only the translated text. Do not wrap the answer in Markdown.

        \(text)
        """
    }

    private func translationSystemPrompt(targetLanguage: String) -> String {
        if isPersianTargetLanguage(targetLanguage) {
            return """
            You are an expert literary translator into Persian.
            Translate into smooth, natural, contemporary Persian that reads like a professionally edited book.
            Do not translate word-for-word when it makes Persian sound stiff or unnatural.
            Preserve the author's meaning, tone, paragraph structure, names, numbers, citations, and references.
            Keep technical or proper nouns stable when translating them would be misleading.
            Return only the requested output format, without explanations or Markdown.
            """
        }

        return """
        You are an expert literary translator into \(targetLanguage).
        Translate naturally and fluently, preserving the author's meaning, tone, paragraph structure, names, numbers, citations, and references.
        Return only the requested output format, without explanations or Markdown.
        """
    }

    private func languageStyleInstruction(targetLanguage: String) -> String {
        if isPersianTargetLanguage(targetLanguage) {
            return "Because the target language is Persian, use fluent, natural Persian prose rather than literal word-by-word translation."
        }

        return "Use fluent, natural \(targetLanguage) rather than literal word-by-word translation."
    }

    private func isPersianTargetLanguage(_ targetLanguage: String) -> Bool {
        let normalized = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("persian") ||
            normalized.contains("farsi") ||
            normalized.contains("فارسی")
    }

    private func endpointURL(path: String) -> URL? {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            normalized = "https://api.openai.com/v1"
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return URL(string: normalized + path)
    }

    private func outputResult(from data: Data) throws -> AIOutputResult {
        switch apiStyle {
        case .responses:
            let responsePayload = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            if let refusal = responsePayload.refusalText {
                throw OpenAIClientError.refusal(refusal)
            }
            return AIOutputResult(
                text: responsePayload.outputText,
                usage: responsePayload.usage?.aiUsage(cost: providerReportedCost(from: data))
            )
        case .chatCompletions:
            let responsePayload = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            if let refusal = responsePayload.refusalText {
                throw OpenAIClientError.refusal(refusal)
            }
            return AIOutputResult(
                text: responsePayload.outputText,
                usage: responsePayload.usage?.aiUsage(cost: providerReportedCost(from: data))
            )
        }
    }

    private func providerReportedCost(from data: Data) -> ProviderReportedCost? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let preferredKeys = [
            "total_cost_toman",
            "total_cost_usd",
            "total_cost",
            "cost_toman",
            "cost_usd",
            "cost"
        ]

        for key in preferredKeys {
            if let cost = findProviderReportedCost(in: json, matchingKey: key) {
                return cost
            }
        }

        return findProviderReportedCost(in: json)
    }

    private func findProviderReportedCost(in value: Any, matchingKey expectedKey: String) -> ProviderReportedCost? {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let normalizedKey = key.lowercased()
                if normalizedKey == expectedKey,
                   let amount = numericValue(from: nestedValue) {
                    return ProviderReportedCost(
                        amount: amount,
                        currency: currencyName(from: normalizedKey)
                    )
                }

                if let nestedCost = findProviderReportedCost(in: nestedValue, matchingKey: expectedKey) {
                    return nestedCost
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let nestedCost = findProviderReportedCost(in: item, matchingKey: expectedKey) {
                    return nestedCost
                }
            }
        }

        return nil
    }

    private func findProviderReportedCost(in value: Any) -> ProviderReportedCost? {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let normalizedKey = key.lowercased()
                if normalizedKey.contains("cost") || normalizedKey.contains("price") {
                    if let amount = numericValue(from: nestedValue) {
                        return ProviderReportedCost(
                            amount: amount,
                            currency: currencyName(from: normalizedKey)
                        )
                    }
                }

                if let nestedCost = findProviderReportedCost(in: nestedValue) {
                    return nestedCost
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let nestedCost = findProviderReportedCost(in: item) {
                    return nestedCost
                }
            }
        }

        return nil
    }

    private func numericValue(from value: Any) -> Double? {
        if let double = value as? Double {
            return double
        }

        if let int = value as? Int {
            return Double(int)
        }

        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private func currencyName(from key: String) -> String? {
        if key.contains("usd") {
            return "USD"
        }

        if key.contains("toman") {
            return "toman"
        }

        if key.contains("irr") || key.contains("rial") {
            return "IRR"
        }

        return nil
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
            "AI provider returned retryable HTTP \(statusCode): \(message)"
        }
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}

private struct ModelListResponse: Decodable {
    let data: [ModelItem]

    struct ModelItem: Decodable {
        let id: String
    }
}

private struct AIOutputResult {
    let text: String?
    let usage: AIUsage?
}

private struct ProviderReportedCost {
    let amount: Double
    let currency: String?
}

private struct OpenAIResponse: Decodable {
    let output: [OutputItem]
    let usage: ResponsesUsage?

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

private struct ResponsesUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    func aiUsage(cost: ProviderReportedCost?) -> AIUsage {
        AIUsage(
            inputTokens: inputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            totalTokens: totalTokens ?? ((inputTokens ?? 0) + (outputTokens ?? 0)),
            providerReportedCost: cost?.amount,
            costCurrency: cost?.currency
        )
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
    let usage: ChatUsage?

    var outputText: String? {
        choices.compactMap(\.message.content).first { !$0.isEmpty }
    }

    var refusalText: String? {
        choices.compactMap(\.message.refusal).first { !$0.isEmpty }
    }

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
        let refusal: String?
    }
}

private struct ChatUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }

    func aiUsage(cost: ProviderReportedCost?) -> AIUsage {
        AIUsage(
            inputTokens: promptTokens ?? 0,
            outputTokens: completionTokens ?? 0,
            totalTokens: totalTokens ?? ((promptTokens ?? 0) + (completionTokens ?? 0)),
            providerReportedCost: cost?.amount,
            costCurrency: cost?.currency
        )
    }
}
