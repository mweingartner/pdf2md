import Foundation
import PDFKit
import AppKit

// MARK: - Data Types

/// A single run of text with uniform font attributes from a PDF page.
struct TextRun {
    let text: String
    let fontSize: CGFloat
    let isBold: Bool
    let isItalic: Bool
    let pageIndex: Int
}

/// All text content extracted from a single PDF page.
struct PageContent {
    let pageIndex: Int
    let textRuns: [TextRun]
}

/// Statistics derived from analyzing font usage across the document.
/// The body font size is the most common size (by character count).
/// Heading sizes are the top 3 sizes larger than body, mapped to H1–H3.
struct FontStatistics {
    let bodyFontSize: CGFloat
    let headingSizes: [CGFloat]  // sorted descending, mapped to H1, H2, H3

    /// Returns the heading level (1–3) for a given font size, or nil if it is not a heading.
    func headingLevel(for fontSize: CGFloat) -> Int? {
        for (index, size) in headingSizes.enumerated() {
            // Allow a small tolerance for floating-point rounding
            if abs(fontSize - size) < 0.5 {
                return index + 1
            }
        }
        return nil
    }
}

// MARK: - PDF Extractor

/// Extracts structured text content from a PDFDocument, including font metadata
/// needed to reconstruct headings, bold, and italic formatting.
struct PDFExtractor {

    // MARK: - Public Interface

    /// Extracts page content from every page of the given document.
    /// - Parameter document: A fully loaded PDFDocument.
    /// - Returns: An array of PageContent, one per page, in page order.
    func extractPages(from document: PDFDocument) -> [PageContent] {
        let pageCount = document.pageCount
        var pages: [PageContent] = []
        pages.reserveCapacity(pageCount)

        for index in 0 ..< pageCount {
            guard let page = document.page(at: index) else { continue }
            let content = extractPageContent(page: page, pageIndex: index)
            pages.append(content)
        }
        return pages
    }

    /// Analyzes font sizes across all extracted pages to determine body and heading sizes.
    /// - Parameter pages: The full array of PageContent from the document.
    /// - Returns: A FontStatistics instance describing body and heading font sizes.
    func analyzeFont(from pages: [PageContent]) -> FontStatistics {
        // Build a frequency histogram weighted by character count.
        // Keys are font sizes rounded to the nearest 0.5pt.
        var sizeCharCount: [CGFloat: Int] = [:]

        for page in pages {
            for run in page.textRuns {
                let rounded = roundedSize(run.fontSize)
                sizeCharCount[rounded, default: 0] += run.text.count
            }
        }

        guard !sizeCharCount.isEmpty else {
            return FontStatistics(bodyFontSize: 12, headingSizes: [])
        }

        // The mode (most frequent by char count) is the body size.
        let bodySize = sizeCharCount.max(by: { $0.value < $1.value })!.key

        // Heading candidates: sizes more than 1.5pt larger than body.
        let headingThreshold = bodySize + 1.5
        let headingCandidates = sizeCharCount.keys
            .filter { $0 > headingThreshold }
            .sorted(by: >)  // descending: largest = H1

        let headingSizes = Array(headingCandidates.prefix(3))
        return FontStatistics(bodyFontSize: bodySize, headingSizes: headingSizes)
    }

    /// Identifies text runs that appear to be headers or footers repeating across pages.
    ///
    /// A run is a candidate header/footer when its trimmed text matches content
    /// appearing in the first or last position on more than 60% of all pages.
    /// Standalone page numbers (digits only) are also included.
    ///
    /// - Parameter pages: The full array of PageContent.
    /// - Returns: A set of trimmed strings that should be treated as header/footer noise.
    func detectHeadersFooters(from pages: [PageContent]) -> Set<String> {
        guard pages.count > 1 else { return [] }

        let totalPages = pages.count
        let threshold = Int(ceil(Double(totalPages) * 0.6))

        // Gather first and last text runs per page
        var firstTextCounts: [String: Int] = [:]
        var lastTextCounts: [String: Int] = [:]
        let pageNumberPattern = try? NSRegularExpression(pattern: #"^\s*\d+\s*$"#)

        for page in pages {
            let nonEmpty = page.textRuns.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if let first = nonEmpty.first {
                let key = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    firstTextCounts[key, default: 0] += 1
                }
            }
            if let last = nonEmpty.last {
                let key = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    lastTextCounts[key, default: 0] += 1
                }
            }
        }

        var headersFooters: Set<String> = []

        for (text, count) in firstTextCounts where count >= threshold {
            headersFooters.insert(text)
        }
        for (text, count) in lastTextCounts where count >= threshold {
            headersFooters.insert(text)
        }

        // Also add any standalone page number patterns found in first/last positions
        for page in pages {
            let nonEmpty = page.textRuns.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            for candidate in [nonEmpty.first, nonEmpty.last].compactMap({ $0 }) {
                let key = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let regex = pageNumberPattern {
                    let range = NSRange(key.startIndex..., in: key)
                    if regex.firstMatch(in: key, range: range) != nil {
                        headersFooters.insert(key)
                    }
                }
            }
        }

        return headersFooters
    }

    // MARK: - Private Helpers

    private func extractPageContent(page: PDFPage, pageIndex: Int) -> PageContent {
        // PDFPage.attributedString provides the full page text with font attributes.
        guard let attributedString = page.attributedString, attributedString.length > 0 else {
            return PageContent(pageIndex: pageIndex, textRuns: [])
        }

        var textRuns: [TextRun] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)

        // Enumerate .font attribute to extract runs with uniform font properties.
        attributedString.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let nsFont = value as? NSFont else { return }
            guard let substring = Range(range, in: attributedString.string) else { return }

            let text = String(attributedString.string[substring])
            guard !text.isEmpty else { return }

            let fontSize = nsFont.pointSize
            let traits = nsFont.fontDescriptor.symbolicTraits
            let isBold = traits.contains(.bold)
            let isItalic = traits.contains(.italic)

            let run = TextRun(
                text: text,
                fontSize: fontSize,
                isBold: isBold,
                isItalic: isItalic,
                pageIndex: pageIndex
            )
            textRuns.append(run)
        }

        return PageContent(pageIndex: pageIndex, textRuns: textRuns)
    }

    /// Rounds a font size to the nearest 0.5pt for histogram bucketing.
    private func roundedSize(_ size: CGFloat) -> CGFloat {
        return (size * 2).rounded() / 2
    }
}
