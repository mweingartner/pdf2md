import Foundation

actor PDFMonitorService {
    private let conversionService = PDFConversionService()
    private let fileManager = FileManager.default
    private var monitorTask: Task<Void, Never>?
    private let minimumFileAgeForProcessing: TimeInterval = 2

    func start(
        configuration: MonitorConfiguration,
        eventHandler: @escaping @Sendable (MonitorEvent) -> Void
    ) {
        monitorTask?.cancel()
        eventHandler(.monitoringStarted)

        monitorTask = Task {
            await scan(configuration: configuration, eventHandler: eventHandler)

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(configuration.scanIntervalSeconds))
                await scan(configuration: configuration, eventHandler: eventHandler)
            }
        }
    }

    func stop(eventHandler: (@Sendable (MonitorEvent) -> Void)? = nil) {
        monitorTask?.cancel()
        monitorTask = nil
        eventHandler?(.monitoringStopped)
    }

    func scanOnce(
        configuration: MonitorConfiguration,
        eventHandler: @escaping @Sendable (MonitorEvent) -> Void
    ) async {
        await scan(configuration: configuration, eventHandler: eventHandler)
    }

    private func scan(
        configuration: MonitorConfiguration,
        eventHandler: @escaping @Sendable (MonitorEvent) -> Void
    ) async {
        guard
            let sourceDirectory = configuration.sourceDirectoryURL,
            let outputDirectory = configuration.outputDirectoryURL,
            let processedDirectory = configuration.processedDirectoryURL
        else {
            return
        }

        let sourceRoot = sourceDirectory.standardizedFileURL
        let outputRoot = outputDirectory.standardizedFileURL
        let processedRoot = processedDirectory.standardizedFileURL

        do {
            let pdfURLs = try discoverPendingPDFs(
                in: sourceRoot,
                excluding: [outputRoot, processedRoot]
            )

            guard !pdfURLs.isEmpty else {
                eventHandler(.waitingForPDFs)
                return
            }

            for pdfURL in pdfURLs {
                if Task.isCancelled {
                    return
                }

                do {
                    let outputURL = try buildMirroredURL(
                        for: pdfURL,
                        relativeTo: sourceRoot,
                        under: outputRoot,
                        pathExtension: "md"
                    )
                    let archivedURL = try buildMirroredURL(
                        for: pdfURL,
                        relativeTo: sourceRoot,
                        under: processedRoot,
                        pathExtension: pdfURL.pathExtension
                    )

                    let resolvedOutputURL = try uniqueURL(for: outputURL)
                    let resolvedArchivedURL = try uniqueURL(for: archivedURL)

                    _ = try conversionService.convertPDF(at: pdfURL, outputURL: resolvedOutputURL)
                    try moveItem(at: pdfURL, to: resolvedArchivedURL)

                    eventHandler(.converted(
                        sourcePath: pdfURL.path,
                        outputPath: resolvedOutputURL.path,
                        archivedPath: resolvedArchivedURL.path
                    ))
                } catch let error as ConversionError {
                    eventHandler(.failed(sourcePath: pdfURL.path, message: error.userMessage))
                } catch {
                    eventHandler(.failed(sourcePath: pdfURL.path, message: error.localizedDescription))
                }
            }
        } catch {
            eventHandler(.failed(sourcePath: sourceRoot.path, message: error.localizedDescription))
        }
    }

    private func discoverPendingPDFs(in sourceRoot: URL, excluding excludedDirectories: [URL]) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var pdfURLs: [URL] = []
        let now = Date()

        for case let candidateURL as URL in enumerator {
            let standardizedCandidateURL = candidateURL.standardizedFileURL

            if shouldSkipDescendants(of: standardizedCandidateURL, excludedDirectories: excludedDirectories) {
                enumerator.skipDescendants()
                continue
            }

            let resourceValues = try standardizedCandidateURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .contentModificationDateKey,
            ])

            if resourceValues.isDirectory == true {
                continue
            }

            guard resourceValues.isRegularFile == true else {
                continue
            }

            guard standardizedCandidateURL.pathExtension.compare("pdf", options: .caseInsensitive) == .orderedSame else {
                continue
            }

            if let modificationDate = resourceValues.contentModificationDate,
               now.timeIntervalSince(modificationDate) < minimumFileAgeForProcessing {
                continue
            }

            pdfURLs.append(standardizedCandidateURL)
        }

        return pdfURLs.sorted { $0.path < $1.path }
    }

    private func shouldSkipDescendants(of candidateURL: URL, excludedDirectories: [URL]) -> Bool {
        excludedDirectories.contains { excludedDirectory in
            isSameDirectory(candidateURL, as: excludedDirectory) || isDescendant(candidateURL, of: excludedDirectory)
        }
    }

    private func buildMirroredURL(
        for sourceFile: URL,
        relativeTo sourceRoot: URL,
        under targetRoot: URL,
        pathExtension: String
    ) throws -> URL {
        let relativeParentComponents = try relativeParentComponents(for: sourceFile, relativeTo: sourceRoot)
        var targetDirectory = targetRoot

        for component in relativeParentComponents {
            targetDirectory.appendPathComponent(component, isDirectory: true)
        }

        let baseName = sourceFile.deletingPathExtension().lastPathComponent
        return targetDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension(pathExtension)
    }

    private func relativeParentComponents(for sourceFile: URL, relativeTo sourceRoot: URL) throws -> [String] {
        let standardizedSourceRoot = sourceRoot.standardizedFileURL.path
        let standardizedParentPath = sourceFile.deletingLastPathComponent().standardizedFileURL.path

        guard standardizedParentPath == standardizedSourceRoot || standardizedParentPath.hasPrefix(standardizedSourceRoot + "/") else {
            throw ConversionError.outputPathEscapeAttempt
        }

        let relativeParentPath = standardizedParentPath.dropFirst(standardizedSourceRoot.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !relativeParentPath.isEmpty else {
            return []
        }

        return relativeParentPath.split(separator: "/").map(String.init)
    }

    private func uniqueURL(for preferredURL: URL) throws -> URL {
        let parentDirectory = preferredURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: preferredURL.path) else {
            let baseName = preferredURL.deletingPathExtension().lastPathComponent
            let pathExtension = preferredURL.pathExtension

            for index in 1...10_000 {
                let candidateURL = parentDirectory
                    .appendingPathComponent("\(baseName)-\(index)")
                    .appendingPathExtension(pathExtension)

                if !fileManager.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
            }

            throw ConversionError.writeFailed
        }

        return preferredURL
    }

    private func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                try fileManager.removeItem(at: sourceURL)
            } catch {
                throw ConversionError.writeFailed
            }
        }
    }

    private func isSameDirectory(_ lhs: URL, as rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private func isDescendant(_ candidateURL: URL, of rootURL: URL) -> Bool {
        candidateURL.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/")
    }
}
