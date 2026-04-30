import Foundation

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
            return "The output path is invalid."
        case .writeFailed:
            return "Failed to write the output file. Check disk space and directory permissions."
        }
    }
}
