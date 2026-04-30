import Foundation

// MARK: - Entry Point

func main() {
    let args = CommandLine.arguments

    // Expect exactly one argument: the PDF file path
    guard args.count == 2 else {
        fputs("Usage: pdf2md <path-to-pdf>\n", stderr)
        exit(1)
    }

    let inputPath = args[1]
    let conversionService = PDFConversionService()

    do {
        let outputPath = try conversionService.convertPDF(at: inputPath)
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

// MARK: - Run

main()
