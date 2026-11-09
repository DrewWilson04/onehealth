import Foundation
import PulseCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Plain-language phrasing of a stats-engine finding.
public struct PhrasedInsight: Sendable, Hashable {
    public var headline: String
    public var explanation: String
    public var suggestion: String?
    public var usedModel: Bool
}

/// Uses the on-device language model ONLY to phrase and explain findings.
///
/// Numbers never come from the model: the model sees the finding with
/// `[[token]]` placeholders instead of values and must reuse those tokens.
/// Any output containing a digit, or an unknown token, is rejected and the
/// engine's deterministic wording is used instead. No network calls.
public actor InsightPhraser {
    private var cache: [String: PhrasedInsight] = [:]
    public init() {}

    public static func deterministic(_ f: Finding) -> PhrasedInsight {
        PhrasedInsight(headline: headline(f), explanation: f.text, suggestion: nil, usedModel: false)
    }

    static func headline(_ f: Finding) -> String {
        switch f.kind {
        case .anomaly: return "Unusual \(FormatToken.name(f.outcome)) today"
        case .trendChange: return "\(FormatToken.name(f.outcome).capitalizedFirst) is changing"
        case .conditional, .correlation: return "A pattern in your \(FormatToken.name(f.outcome))"
        }
    }

    public static func validateAndFill(_ text: String, tokens: [String: String]) -> String? {
        InsightValidation.validateAndFill(text, tokens: tokens)
    }

    public func phrase(_ f: Finding) async -> PhrasedInsight {
        let key = "\(f.id)|\(f.values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))"
        if let c = cache[key] { return c }
        var result = Self.deterministic(f)
        #if canImport(FoundationModels) && !os(watchOS)
        if case .available = SystemLanguageModel.default.availability, let p = await modelPhrase(f) {
            result = p
        }
        #endif
        cache[key] = result
        return result
    }

    #if canImport(FoundationModels) && !os(watchOS)
    @Generable
    struct Phrasing {
        @Guide(description: "A short, friendly headline of at most 8 words. Never write digits; refer to numbers only with the provided [[tokens]].")
        var headline: String
        @Guide(description: "One or two plain-language sentences explaining the observation to a non-expert. Reuse the provided [[tokens]] for every number. Never write digits. Do not diagnose or give medical advice.")
        var explanation: String
        @Guide(description: "One gentle, practical, non-medical suggestion phrased as an option the user could try, or an empty string. Never write digits.")
        var suggestion: String
    }

    private func modelPhrase(_ f: Finding) async -> PhrasedInsight? {
        let instructions = """
        You rewrite facts from a personal health dashboard into warm, clear, plain language.
        Rules: Use ONLY the facts given. Numbers are shown as tokens like [[effect]] — copy tokens exactly and never write digits.
        Do not add new facts, causes, diagnoses or medical advice. Say "tends to" or "seems" for patterns; they are correlations, not proof.
        """
        let tokenHelp = f.values.keys.sorted().map { "[[\($0)]]" }.joined(separator: ", ")
        let prompt = """
        Fact (with number tokens): \(f.template)
        Available tokens: \(tokenHelp)
        Kind: \(f.kind.rawValue). Metric: \(FormatToken.name(f.outcome)).
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: Phrasing.self)
            let p = response.content
            guard let h = Self.validateAndFill(p.headline, tokens: f.values),
                  let e = Self.validateAndFill(p.explanation, tokens: f.values),
                  let s = Self.validateAndFill(p.suggestion, tokens: f.values) else { return nil }
            // The explanation must mention at least one engine number when the fact has numbers.
            if !f.values.isEmpty && !p.explanation.contains("[[") { return nil }
            return PhrasedInsight(headline: h, explanation: e, suggestion: s.isEmpty ? nil : s, usedModel: true)
        } catch {
            return nil
        }
    }
    #endif
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
