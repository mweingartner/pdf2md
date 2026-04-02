import Foundation
import PDFKit

// MARK: - Constants

private let pdfMagicBytes: [UInt8] = [0x25, 0x50, 0x44, 0x46, 0x2D]  // "%PDF-"
private let maxPageCountWarningThreshold = 2000

// MARK: - Entry Point

func main() {
    let args = CommandLine.arguments

    // Expect exactly one argument: the PDF file path
    guard args.count == 2 else {
        fputs("Usage: pdf2md <path-to-pdf>\n", stderr)
        exit(1)
    }

    let inputPath = args[1]

    do {
        let outputPath = try convertPDF(at: inputPath)
        print(outputPath)
        exit(0)
    } catch let error as ConversionError {
        fputs("Error: \(error.userMessage)\n", stderr)
        exit(1)
    } catch {
        fputs("Error: An unexpected error occurred during conversion.\n", stderr)
        exit(1)
    }
}

// MARK: - Conversion Error

/// User-friendly, sanitized error type. Internal details (NSError codes, stack
/// traces, file-system internals) are never included in the message.
enum ConversionError: Error {
    case fileNotFound
    case fileNotReadable
    case invalidPDFFormat
    case encryptedPDF
    case emptyDocument
    case outputPathEscapeAttempt
    case writeFailed

    var userMessage: String {
        switch self {
        case .fileNotFound:
            return "The specified file could not be found."
        case .fileNotReadable:
            return "The file could not be read. Check file permissions."
        case .invalidPDFFormat:
            return "The file does not appear to be a valid PDF."
        case .encryptedPDF:
            return "The PDF is password-protected and cannot be converted."
        case .emptyDocument:
            return "The PDF contains no extractable text."
        case .outputPathEscapeAttempt:
            return "The output path is invalid — it must remain in the same directory as the input file."
        case .writeFailed:
            return "Failed to write the output file. Check disk space and directory permissions."
        }
    }
}

// MARK: - Core Conversion

/// Validates, extracts, formats, cleans, and writes a Markdown file for the given PDF.
/// - Parameter inputPath: Absolute or relative path to the source PDF file.
/// - Returns: The absolute path of the written Markdown file.
/// - Throws: `ConversionError` on any validation or processing failure.
func convertPDF(at inputPath: String) throws -> String {
    // Resolve the input URL to an absolute path
    let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL

    // 1. Validate: file exists and is readable
    let fm = FileManager.default
    guard fm.fileExists(atPath: inputURL.path) else {
        throw ConversionError.fileNotFound
    }
    guard fm.isReadableFile(atPath: inputURL.path) else {
        throw ConversionError.fileNotReadable
    }

    // 2. Validate: check PDF magic bytes (%PDF-) before handing to PDFKit (Security M-2)
    try validatePDFMagicBytes(at: inputURL)

    // 3. Open with PDFKit
    guard let document = PDFDocument(url: inputURL) else {
        throw ConversionError.invalidPDFFormat
    }

    // 4. Reject encrypted documents
    guard !document.isEncrypted else {
        throw ConversionError.encryptedPDF
    }

    // 5. Check page count; warn if very large (Security M-3)
    let pageCount = document.pageCount
    if pageCount > maxPageCountWarningThreshold {
        fputs("Warning: This document has \(pageCount) pages. Conversion may take a while.\n", stderr)
    }

    guard pageCount > 0 else {
        throw ConversionError.emptyDocument
    }

    // 6. Construct and validate output path (Security H-1)
    let outputURL = try buildAndValidateOutputURL(from: inputURL)

    // 7. Extract, analyze, format, clean
    let extractor = PDFExtractor()
    let pages = extractor.extractPages(from: document)

    let fontStats = extractor.analyzeFont(from: pages)
    let headersFooters = extractor.detectHeadersFooters(from: pages)

    let formatter = MarkdownFormatter()
    let rawMarkdown = formatter.format(pages: pages, fontStats: fontStats, headersFooters: headersFooters)

    let cleaner = TextCleaner()
    let cleanedMarkdown = cleaner.clean(rawMarkdown)

    // 8. Write output
    do {
        try cleanedMarkdown.write(to: outputURL, atomically: true, encoding: .utf8)
    } catch {
        throw ConversionError.writeFailed
    }

    return outputURL.path
}

// MARK: - Validation Helpers

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

/// Builds the output .md URL from the input URL and validates that the resolved
/// output path remains within the same directory as the input (Security H-1).
/// - Returns: The validated output URL.
/// - Throws: `ConversionError.outputPathEscapeAttempt` if the path escapes the input directory.
private func buildAndValidateOutputURL(from inputURL: URL) throws -> URL {
    let inputDir = inputURL.deletingLastPathComponent()
    let baseName = inputURL.deletingPathExtension().lastPathComponent

    // Resolve the input directory's symlinks first, then append the filename.
    // Resolving the directory (which exists) is reliable; resolving a full output
    // path that does not exist yet stops at the missing component and fails to
    // dereference parent symlinks.
    let resolvedInputDir = inputDir.resolvingSymlinksInPath()
    let resolvedOutputURL = resolvedInputDir
        .appendingPathComponent(baseName)
        .appendingPathExtension("md")

    // Confirm the output's parent directory matches the resolved input directory.
    let outputParent = resolvedOutputURL.deletingLastPathComponent()
    guard outputParent.path == resolvedInputDir.path else {
        throw ConversionError.outputPathEscapeAttempt
    }

    return resolvedOutputURL
}

// MARK: - Run

main()
