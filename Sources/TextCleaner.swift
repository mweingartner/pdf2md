import Foundation

// MARK: - Text Cleaner

/// Applies a series of post-processing cleaning steps to the raw Markdown output
/// produced by MarkdownFormatter. Cleaning is applied in a specific order to avoid
/// interference between steps.
///
/// Steps applied (in order):
/// 1. Fix hyphenated line breaks (`word-\n` → joined word)
/// 2. Remove soft hyphens (U+00AD)
/// 3. Normalize Unicode whitespace to regular ASCII spaces
/// 4. Fix common ligature characters (ﬁ, ﬂ, ﬀ, ﬃ, ﬄ)
/// 5. Collapse 3+ consecutive blank lines to 2
/// 6. Remove trailing whitespace from each line
/// 7. Fix spaced-out heading characters (PDF artifact: `I  n  t  r  o`)
/// 8. Ensure the file ends with exactly one newline
struct TextCleaner {

    // MARK: - Public Interface

    /// Cleans the given Markdown string and returns the cleaned result.
    /// - Parameter text: Raw Markdown as produced by MarkdownFormatter.
    /// - Returns: The cleaned Markdown string.
    func clean(_ text: String) -> String {
        var result = text

        result = fixHyphenatedLineBreaks(result)
        result = removeSoftHyphens(result)
        result = normalizeUnicodeWhitespace(result)
        result = fixLigatures(result)
        result = collapseExcessiveBlankLines(result)
        result = removeTrailingWhitespace(result)
        result = fixSpacedHeadingCharacters(result)
        result = ensureSingleTrailingNewline(result)

        return result
    }

    // MARK: - Cleaning Steps

    /// Rejoins words broken by hyphenation at line endings.
    /// Example: `hyphen-\nated` → `hyphenated`
    private func fixHyphenatedLineBreaks(_ text: String) -> String {
        // Pattern: a word character, a hyphen, end-of-line, optional whitespace, a word character
        guard let regex = try? NSRegularExpression(
            pattern: #"(\w)-\n\s*(\w)"#,
            options: []
        ) else { return text }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1$2")
    }

    /// Removes soft hyphen characters (U+00AD) which PDFKit sometimes produces.
    private func removeSoftHyphens(_ text: String) -> String {
        return text.replacingOccurrences(of: "\u{00AD}", with: "")
    }

    /// Converts Unicode whitespace variants to regular ASCII spaces.
    /// Handles non-breaking space (U+00A0), en space, em space, thin space,
    /// zero-width space, zero-width non-breaking space (BOM), and similar.
    private func normalizeUnicodeWhitespace(_ text: String) -> String {
        var result = text

        // Non-breaking space and common Unicode spaces
        let unicodeSpaces: [Character] = [
            "\u{00A0}",  // Non-breaking space
            "\u{2002}",  // En space
            "\u{2003}",  // Em space
            "\u{2004}",  // Three-per-em space
            "\u{2005}",  // Four-per-em space
            "\u{2006}",  // Six-per-em space
            "\u{2007}",  // Figure space
            "\u{2008}",  // Punctuation space
            "\u{2009}",  // Thin space
            "\u{200A}",  // Hair space
            "\u{200B}",  // Zero-width space
            "\u{FEFF}",  // Zero-width no-break space (BOM)
        ]

        for ch in unicodeSpaces {
            result = result.replacingOccurrences(of: String(ch), with: " ")
        }

        return result
    }

    /// Replaces common typographic ligature characters with their ASCII equivalents.
    private func fixLigatures(_ text: String) -> String {
        var result = text

        let ligatures: [(String, String)] = [
            ("\u{FB01}", "fi"),   // ﬁ
            ("\u{FB02}", "fl"),   // ﬂ
            ("\u{FB00}", "ff"),   // ﬀ
            ("\u{FB03}", "ffi"),  // ﬃ
            ("\u{FB04}", "ffl"),  // ﬄ
            ("\u{FB05}", "st"),   // ﬅ (long s + t)
            ("\u{FB06}", "st"),   // ﬆ (s + t)
        ]

        for (ligature, replacement) in ligatures {
            result = result.replacingOccurrences(of: ligature, with: replacement)
        }

        return result
    }

    /// Collapses runs of 3 or more consecutive blank lines to exactly 2 blank lines.
    private func collapseExcessiveBlankLines(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\n[ \t]*){3,}"#,
            options: []
        ) else { return text }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n\n\n")
    }

    /// Removes trailing whitespace from every line.
    private func removeTrailingWhitespace(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let cleaned = lines.map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
        return cleaned.joined(separator: "\n")
    }

    /// Fixes PDF artifacts where headings have extra spaces inserted between characters.
    ///
    /// PDFs sometimes render "Introduction" as "I n t r o d u c t i o n" — individual
    /// characters separated by spaces. This detects heading lines (starting with `#`)
    /// where the majority of "words" are single characters and collapses them.
    private func fixSpacedHeadingCharacters(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let cleaned = lines.map { line -> String in
            // Only process lines that start with one or more # characters (heading lines)
            guard line.hasPrefix("#") else { return line }

            // Split off the # prefix from the heading content
            let prefixEnd = line.firstIndex(where: { $0 != "#" && $0 != " " }) ?? line.endIndex
            let hashPrefix = String(line[line.startIndex ..< prefixEnd])
            let content = String(line[prefixEnd...])

            let words = content.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count >= 4 else { return line }

            let singleCharCount = words.filter { $0.count == 1 }.count
            let ratio = Double(singleCharCount) / Double(words.count)

            // If more than 60% of the "words" are single characters, collapse the spaces
            if ratio > 0.6 {
                let collapsed = words.joined()
                return hashPrefix + collapsed
            }
            return line
        }
        return cleaned.joined(separator: "\n")
    }

    /// Ensures the text ends with exactly one newline character.
    private func ensureSingleTrailingNewline(_ text: String) -> String {
        var result = text
        // Strip all trailing newlines then add exactly one
        while result.hasSuffix("\n") {
            result = String(result.dropLast())
        }
        return result + "\n"
    }
}
