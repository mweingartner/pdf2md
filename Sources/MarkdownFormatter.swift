import Foundation

// MARK: - Markdown Formatter

/// Converts structured page content into a clean Markdown string.
///
/// The formatter maps font sizes to heading levels, wraps bold and italic runs
/// in the appropriate Markdown syntax, suppresses identified header/footer text,
/// and groups consecutive body-size runs into paragraphs separated by blank lines.
///
/// No page separator markers are emitted — the output is intentionally clean
/// for LLM consumption.
struct MarkdownFormatter {

    // MARK: - Public Interface

    /// Formats the extracted page content as a Markdown string.
    ///
    /// - Parameters:
    ///   - pages: All pages of extracted text runs.
    ///   - fontStats: Font statistics used to classify heading levels.
    ///   - headersFooters: Set of trimmed strings to suppress as noise.
    /// - Returns: The complete Markdown document as a single string.
    func format(
        pages: [PageContent],
        fontStats: FontStatistics,
        headersFooters: Set<String>
    ) -> String {
        var outputLines: [String] = []

        // Page number regex for fast inline checks
        let pageNumberRegex = try? NSRegularExpression(pattern: #"^\s*\d+\s*$"#)

        for page in pages {
            var paragraphBuffer: [String] = []

            func flushParagraph() {
                guard !paragraphBuffer.isEmpty else { return }
                let combined = paragraphBuffer.joined(separator: " ")
                let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    outputLines.append(trimmed)
                    outputLines.append("")  // blank line after paragraph
                }
                paragraphBuffer.removeAll()
            }

            for run in page.textRuns {
                let trimmedText = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty else { continue }

                // Skip header/footer noise
                if headersFooters.contains(trimmedText) {
                    flushParagraph()
                    continue
                }

                // Skip standalone page numbers
                if let regex = pageNumberRegex {
                    let range = NSRange(trimmedText.startIndex..., in: trimmedText)
                    if regex.firstMatch(in: trimmedText, range: range) != nil {
                        flushParagraph()
                        continue
                    }
                }

                // Determine if this run is a heading
                if let level = fontStats.headingLevel(for: run.fontSize) {
                    // Flush any buffered body text before emitting a heading
                    flushParagraph()

                    let prefix = String(repeating: "#", count: level)
                    outputLines.append("\(prefix) \(trimmedText)")
                    outputLines.append("")  // blank line after heading
                } else {
                    // Body text: apply bold/italic inline markup, then buffer
                    let marked = applyInlineMarkup(text: trimmedText, isBold: run.isBold, isItalic: run.isItalic)
                    paragraphBuffer.append(marked)
                }
            }

            // Flush any remaining paragraph at end of page
            flushParagraph()
        }

        // Join all lines into a document string
        var result = outputLines.joined(separator: "\n")

        // Ensure the document ends with exactly one newline
        if !result.hasSuffix("\n") {
            result += "\n"
        }

        return result
    }

    // MARK: - Private Helpers

    /// Wraps text in bold and/or italic Markdown markers as appropriate.
    private func applyInlineMarkup(text: String, isBold: Bool, isItalic: Bool) -> String {
        switch (isBold, isItalic) {
        case (true, true):
            return "***\(text)***"
        case (true, false):
            return "**\(text)**"
        case (false, true):
            return "*\(text)*"
        case (false, false):
            return text
        }
    }
}
