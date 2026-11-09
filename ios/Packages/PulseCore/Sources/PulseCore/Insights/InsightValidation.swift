import Foundation

/// Guards the AI phrasing layer: model output may only reference numbers via
/// the stats engine's `[[tokens]]`. Any digit or unknown token → rejected.
public enum InsightValidation {
    public static func validateAndFill(_ text: String, tokens: [String: String]) -> String? {
        if text.rangeOfCharacter(from: .decimalDigits) != nil { return nil }
        var rest = text[...]
        while let open = rest.range(of: "[[") {
            guard let close = rest.range(of: "]]", range: open.upperBound..<rest.endIndex) else { return nil }
            let name = String(rest[open.upperBound..<close.lowerBound])
            if tokens[name] == nil { return nil }
            rest = rest[close.upperBound...]
        }
        if rest.contains("]]") { return nil }
        return Finding.fill(text, tokens)
    }
}
