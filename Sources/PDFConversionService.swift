import Foundation
import PDFKit

private let pdfMagicBytes: [UInt8] = [0x25, 0x50, 0x44, 0x46, 0x2D]  // "%PDF-"
private let maxPageCountWarningThreshold = 2000

struct PDFConversionService {

    /// Validates, extracts, formats, cleans, and writes a Markdown file for the given PDF.
    /// - Parameters:
    ///   - inputURL: Absolute or relative path to the source PDF file.
    ///   - outputURL: Optional explicit output location for the written Markdown file.
    /// - Returns: The absolute path of the written Markdown file.
    /// - Throws: `ConversionError` on any validation or processing failure.
    func convertPDF(at inputURL: URL, outputURL: URL? = nil) throws -> URL {
        let resolvedInputURL = inputURL.standardizedFileURL

        try validateInputFile(at: resolvedInputURL)
        try validatePDFMagicBytes(at: resolvedInputURL)

        guard let document = PDFDocument(url: resolvedInputURL) else {
            throw ConversionError.invalidPDFFormat
        }

        guard !document.isEncrypted else {
            throw ConversionError.encryptedPDF
        }

        let pageCount = document.pageCount
        if pageCount > maxPageCountWarningThreshold {
            fputs("Warning: This document has \(pageCount) pages. Conversion may take a while.\n", stderr)
        }

        guard pageCount > 0 else {
            throw ConversionError.emptyDocument
        }

        let resolvedOutputURL = try buildOutputURL(for: resolvedInputURL, requestedOutputURL: outputURL)

        let extractor = PDFExtractor()
        let pages = extractor.extractPages(from: document)

        let fontStats = extractor.analyzeFont(from: pages)
        let headersFooters = extractor.detectHeadersFooters(from: pages)

        let formatter = MarkdownFormatter()
        let rawMarkdown = formatter.format(pages: pages, fontStats: fontStats, headersFooters: headersFooters)

        let cleaner = TextCleaner()
        let cleanedMarkdown = cleaner.clean(rawMarkdown)

        do {
            try FileManager.default.createDirectory(
                at: resolvedOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try cleanedMarkdown.write(to: resolvedOutputURL, atomically: true, encoding: .utf8)
        } catch {
            throw ConversionError.writeFailed
        }

        return resolvedOutputURL
    }

    func convertPDF(at inputPath: String, outputPath: String? = nil) throws -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = outputPath.map { URL(fileURLWithPath: $0) }
        return try convertPDF(at: inputURL, outputURL: outputURL).path
    }

    private func validateInputFile(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw ConversionError.fileNotFound
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw ConversionError.fileNotReadable
        }
    }

    /// Reads the first 5 bytes of the file and confirms they match `%PDF-`.
    private func validatePDFMagicBytes(at url: URL) throws {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            throw ConversionError.fileNotReadable
        }
        defer { try? fileHandle.close() }

        let headerData: Data
        if #available(macOS 10.15.4, *) {
            guard let data = try? fileHandle.read(upToCount: 5) else {
                throw ConversionError.fileNotReadable
            }
            headerData = data
        } else {
            headerData = fileHandle.readData(ofLength: 5)
        }

        guard headerData.count >= 5 else {
            throw ConversionError.invalidPDFFormat
        }

        let bytes = [UInt8](headerData)
        guard bytes == pdfMagicBytes else {
            throw ConversionError.invalidPDFFormat
        }
    }

    private func buildOutputURL(for inputURL: URL, requestedOutputURL: URL?) throws -> URL {
        if let requestedOutputURL {
            return try resolveRequestedOutputURL(requestedOutputURL)
        }

        return try buildDefaultOutputURL(from: inputURL)
    }

    /// Builds the output .md URL from the input URL and validates that the resolved
    /// output path remains within the same directory as the input (Security H-1).
    private func buildDefaultOutputURL(from inputURL: URL) throws -> URL {
        let inputDirectory = inputURL.deletingLastPathComponent()
        let baseName = inputURL.deletingPathExtension().lastPathComponent

        let resolvedInputDirectory = inputDirectory.resolvingSymlinksInPath()
        let resolvedOutputURL = resolvedInputDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension("md")

        let outputParent = resolvedOutputURL.deletingLastPathComponent()
        guard outputParent.path == resolvedInputDirectory.path else {
            throw ConversionError.outputPathEscapeAttempt
        }

        return resolvedOutputURL
    }

    private func resolveRequestedOutputURL(_ requestedOutputURL: URL) throws -> URL {
        let standardizedOutputURL = requestedOutputURL.standardizedFileURL
        let outputParent = standardizedOutputURL.deletingLastPathComponent()
        let resolvedParent = outputParent.resolvingSymlinksInPath()

        guard !standardizedOutputURL.lastPathComponent.isEmpty else {
            throw ConversionError.outputPathEscapeAttempt
        }

        return resolvedParent.appendingPathComponent(standardizedOutputURL.lastPathComponent)
    }
}
