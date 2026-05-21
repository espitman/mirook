import Foundation

struct AIUsage: Codable, Equatable {
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var providerReportedCost: Double?
    var costCurrency: String?

    static let zero = AIUsage(
        inputTokens: 0,
        outputTokens: 0,
        totalTokens: 0,
        providerReportedCost: nil,
        costCurrency: nil
    )

    var hasTokens: Bool {
        inputTokens > 0 || outputTokens > 0 || totalTokens > 0
    }

    var hasProviderReportedCost: Bool {
        providerReportedCost != nil
    }

    var hasUsage: Bool {
        hasTokens || hasProviderReportedCost
    }

    var tokenDisplayText: String {
        "\(totalTokens.formatted()) total tokens"
    }

    var costDisplayText: String? {
        guard let providerReportedCost else {
            return nil
        }

        let cost = usesWholeUnitCost
            ? providerReportedCost.formatted(.number.precision(.fractionLength(0)))
            : providerReportedCost.formatted(.number.precision(.fractionLength(0...6)))
        if let costCurrency, !costCurrency.isEmpty {
            return "\(cost) \(costCurrency)"
        }

        return "\(cost) provider cost"
    }

    private var usesWholeUnitCost: Bool {
        costCurrency?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "toman"
    }

    var displayText: String {
        var parts = [
            "\(inputTokens.formatted()) input",
            "\(outputTokens.formatted()) output",
            "\(totalTokens.formatted()) total tokens"
        ]

        if let costDisplayText {
            parts.append(costDisplayText)
        } else {
            parts.append("cost not returned")
        }

        return parts.joined(separator: ", ")
    }

    mutating func add(_ other: AIUsage?) {
        guard let other else { return }

        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens

        if let otherCost = other.providerReportedCost {
            providerReportedCost = (providerReportedCost ?? 0) + otherCost
            costCurrency = costCurrency ?? other.costCurrency
        }
    }
}

struct AITextTranslationResult {
    let text: String
    let usage: AIUsage?
}

struct AIPageTranslationResult {
    let page: TranslatedPage
    let usage: AIUsage?
}
