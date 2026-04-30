import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PDF2MDAppModel {
    private enum DirectoryRole {
        case source
        case output
        case processed
    }

    var sourceDirectory: URL?
    var outputDirectory: URL?
    var processedDirectory: URL?
    var isMonitoring = false
    var statusMessage = "Choose a source folder, output folder, and processed folder."
    var recentEvents: [MonitorLogEntry] = []

    @ObservationIgnored private let configurationFileURL: URL
    @ObservationIgnored private let monitorService = PDFMonitorService()
    @ObservationIgnored private var sourceDirectoryBookmarkData: Data?
    @ObservationIgnored private var outputDirectoryBookmarkData: Data?
    @ObservationIgnored private var processedDirectoryBookmarkData: Data?
    @ObservationIgnored private var activeScopedAccessURLs: [DirectoryRole: URL] = [:]

    private struct ResolvedScopedDirectory {
        let url: URL
        let accessStarted: Bool
    }

    init() {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        configurationFileURL = applicationSupportDirectory
            .appendingPathComponent("PDF2MD", isDirectory: true)
            .appendingPathComponent("monitor-configuration.json")

        loadConfiguration()

        if storedConfiguration.shouldResumeMonitoring, configurationError == nil {
            startMonitoring()
        }
    }

    deinit {
        for url in activeScopedAccessURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    var configurationError: String? {
        guard let sourceDirectory else {
            return "Select a source directory to watch for PDFs."
        }

        guard let outputDirectory else {
            return "Select a directory for converted Markdown files."
        }

        guard let processedDirectory else {
            return "Select a directory where processed PDFs should be moved."
        }

        let sourcePath = sourceDirectory.standardizedFileURL.path
        let outputPath = outputDirectory.standardizedFileURL.path
        let processedPath = processedDirectory.standardizedFileURL.path

        guard sourcePath != outputPath else {
            return "The source and output directories must be different."
        }

        guard sourcePath != processedPath else {
            return "The source and processed directories must be different."
        }

        guard outputPath != processedPath else {
            return "The output and processed directories must be different."
        }

        guard !pathsOverlap(outputPath, processedPath) else {
            return "The output and processed directories must not overlap."
        }

        return nil
    }

    var canStartMonitoring: Bool {
        configurationError == nil
    }

    func chooseSourceDirectory() {
        if let url = presentDirectoryChooser(
            title: "Choose the folder to monitor",
            message: "PDF2MD will watch this folder for incoming PDF files.",
            currentURL: sourceDirectory
        ) {
            storeDirectorySelection(url, for: .source)
        }
    }

    func chooseOutputDirectory() {
        if let url = presentDirectoryChooser(
            title: "Choose the output folder",
            message: "Converted Markdown files will be written here.",
            currentURL: outputDirectory
        ) {
            storeDirectorySelection(url, for: .output)
        }
    }

    func chooseProcessedDirectory() {
        if let url = presentDirectoryChooser(
            title: "Choose the processed PDF folder",
            message: "Original PDFs will be moved here after conversion.",
            currentURL: processedDirectory
        ) {
            storeDirectorySelection(url, for: .processed)
        }
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func startMonitoring() {
        guard let configuration = currentConfiguration() else {
            statusMessage = configurationError ?? "Choose all required directories first."
            return
        }

        do {
            try prepareDirectories(for: configuration)
        } catch {
            statusMessage = "Unable to prepare the selected directories."
            appendLog(message: error.localizedDescription, isError: true)
            return
        }

        isMonitoring = true
        statusMessage = "Monitoring for new PDF files."
        saveConfiguration(shouldResumeMonitoring: true)

        Task { [weak self] in
            guard let self else { return }
            await monitorService.start(configuration: configuration) { event in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        statusMessage = "Monitoring stopped."
        saveConfiguration(shouldResumeMonitoring: false)

        Task { [weak self] in
            guard let self else { return }
            await monitorService.stop { event in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        }
    }

    func scanNow() {
        guard let configuration = currentConfiguration() else {
            statusMessage = configurationError ?? "Choose all required directories first."
            return
        }

        statusMessage = "Scanning for PDF files now."

        Task { [weak self] in
            guard let self else { return }
            await monitorService.scanOnce(configuration: configuration) { event in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        }
    }

    func reveal(_ directory: URL?) {
        guard let directory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private var storedConfiguration: MonitorConfiguration {
        loadStoredConfiguration() ?? MonitorConfiguration()
    }

    private func handle(_ event: MonitorEvent) {
        switch event {
        case .monitoringStarted:
            statusMessage = "Monitoring for new PDF files."
            appendLog(message: "Monitoring started.", isError: false)
        case .monitoringStopped:
            statusMessage = "Monitoring stopped."
            appendLog(message: "Monitoring stopped.", isError: false)
        case .waitingForPDFs:
            if isMonitoring {
                statusMessage = "Monitoring for new PDF files."
            } else {
                statusMessage = "Scan complete. No PDFs were waiting."
            }
        case let .converted(sourcePath, outputPath, archivedPath):
            statusMessage = "Converted \(URL(fileURLWithPath: sourcePath).lastPathComponent)."
            appendLog(
                message: "Converted \(sourcePath) -> \(outputPath), archived at \(archivedPath).",
                isError: false
            )
        case let .failed(sourcePath, message):
            statusMessage = "Failed to process \(URL(fileURLWithPath: sourcePath).lastPathComponent)."
            appendLog(message: "\(sourcePath): \(message)", isError: true)
        }
    }

    private func appendLog(message: String, isError: Bool) {
        recentEvents.insert(
            MonitorLogEntry(timestamp: Date(), message: message, isError: isError),
            at: 0
        )

        if recentEvents.count > 20 {
            recentEvents = Array(recentEvents.prefix(20))
        }
    }

    private func currentConfiguration() -> MonitorConfiguration? {
        guard let sourceDirectory, let outputDirectory, let processedDirectory, configurationError == nil else {
            return nil
        }

        return MonitorConfiguration(
            sourceDirectoryPath: sourceDirectory.path,
            outputDirectoryPath: outputDirectory.path,
            processedDirectoryPath: processedDirectory.path,
            sourceDirectoryBookmarkData: sourceDirectoryBookmarkData,
            outputDirectoryBookmarkData: outputDirectoryBookmarkData,
            processedDirectoryBookmarkData: processedDirectoryBookmarkData,
            shouldResumeMonitoring: isMonitoring
        )
    }

    private func restartMonitoringIfNeeded() {
        guard isMonitoring else { return }
        stopMonitoring()
        startMonitoring()
    }

    private func presentDirectoryChooser(title: String, message: String, currentURL: URL?) -> URL? {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL

        return panel.runModal() == .OK ? panel.url?.standardizedFileURL : nil
    }

    private func prepareDirectories(for configuration: MonitorConfiguration) throws {
        let fileManager = FileManager.default

        guard let sourceDirectory = configuration.sourceDirectoryURL else {
            return
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ConversionError.fileNotFound
        }

        if let outputDirectory = configuration.outputDirectoryURL {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        if let processedDirectory = configuration.processedDirectoryURL {
            try fileManager.createDirectory(at: processedDirectory, withIntermediateDirectories: true)
        }
    }

    private func loadConfiguration() {
        let configuration = storedConfiguration
        restoreDirectory(for: .source, path: configuration.sourceDirectoryPath, bookmarkData: configuration.sourceDirectoryBookmarkData)
        restoreDirectory(for: .output, path: configuration.outputDirectoryPath, bookmarkData: configuration.outputDirectoryBookmarkData)
        restoreDirectory(for: .processed, path: configuration.processedDirectoryPath, bookmarkData: configuration.processedDirectoryBookmarkData)
        isMonitoring = false
    }

    private func loadStoredConfiguration() -> MonitorConfiguration? {
        guard let data = try? Data(contentsOf: configurationFileURL) else {
            return nil
        }

        return try? JSONDecoder().decode(MonitorConfiguration.self, from: data)
    }

    private func saveConfiguration(shouldResumeMonitoring: Bool) {
        let configuration = MonitorConfiguration(
            sourceDirectoryPath: sourceDirectory?.path ?? "",
            outputDirectoryPath: outputDirectory?.path ?? "",
            processedDirectoryPath: processedDirectory?.path ?? "",
            sourceDirectoryBookmarkData: sourceDirectoryBookmarkData,
            outputDirectoryBookmarkData: outputDirectoryBookmarkData,
            processedDirectoryBookmarkData: processedDirectoryBookmarkData,
            shouldResumeMonitoring: shouldResumeMonitoring
        )

        do {
            try FileManager.default.createDirectory(
                at: configurationFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(configuration)
            try data.write(to: configurationFileURL, options: .atomic)
        } catch {
            appendLog(message: "Failed to save configuration: \(error.localizedDescription)", isError: true)
        }
    }

    private func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }

    private func storeDirectorySelection(_ selectedURL: URL, for role: DirectoryRole) {
        do {
            let bookmarkData = try selectedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let resolvedDirectory = try resolveSecurityScopedURL(from: bookmarkData)
                ?? ResolvedScopedDirectory(url: selectedURL.standardizedFileURL, accessStarted: false)

            if resolvedDirectory.url.standardizedFileURL.path == selectedURL.standardizedFileURL.path {
                selectedURL.stopAccessingSecurityScopedResource()
            }

            applyDirectorySelection(
                url: resolvedDirectory.url,
                bookmarkData: bookmarkData,
                accessStarted: resolvedDirectory.accessStarted,
                for: role
            )
            saveConfiguration(shouldResumeMonitoring: isMonitoring)
            restartMonitoringIfNeeded()
        } catch {
            statusMessage = "Unable to save access to the selected folder."
            appendLog(message: "Folder permission error: \(error.localizedDescription)", isError: true)
        }
    }

    private func restoreDirectory(for role: DirectoryRole, path: String, bookmarkData: Data?) {
        guard !path.isEmpty else {
            applyDirectorySelection(url: nil, bookmarkData: nil, accessStarted: false, for: role)
            return
        }

        if let bookmarkData {
            do {
                var bookmarkDataToStore = bookmarkData
                let resolvedDirectory = try resolveSecurityScopedURL(from: bookmarkData)
                    ?? ResolvedScopedDirectory(url: URL(fileURLWithPath: path).standardizedFileURL, accessStarted: false)

                if let refreshedBookmarkData = try refreshedBookmarkDataIfNeeded(for: resolvedDirectory.url, originalData: bookmarkData) {
                    bookmarkDataToStore = refreshedBookmarkData
                }

                applyDirectorySelection(
                    url: resolvedDirectory.url,
                    bookmarkData: bookmarkDataToStore,
                    accessStarted: resolvedDirectory.accessStarted,
                    for: role
                )
                return
            } catch {
                appendLog(message: "Could not restore folder access for \(path): \(error.localizedDescription)", isError: true)
            }
        }

        applyDirectorySelection(
            url: URL(fileURLWithPath: path).standardizedFileURL,
            bookmarkData: nil,
            accessStarted: false,
            for: role
        )
    }

    private func resolveSecurityScopedURL(from bookmarkData: Data) throws -> ResolvedScopedDirectory? {
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL

        return ResolvedScopedDirectory(
            url: resolvedURL,
            accessStarted: resolvedURL.startAccessingSecurityScopedResource()
        )
    }

    private func refreshedBookmarkDataIfNeeded(for url: URL, originalData: Data) throws -> Data? {
        let refreshedData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return refreshedData == originalData ? nil : refreshedData
    }

    private func applyDirectorySelection(url: URL?, bookmarkData: Data?, accessStarted: Bool, for role: DirectoryRole) {
        releaseScopedAccess(for: role)

        switch role {
        case .source:
            sourceDirectory = url
            sourceDirectoryBookmarkData = bookmarkData
        case .output:
            outputDirectory = url
            outputDirectoryBookmarkData = bookmarkData
        case .processed:
            processedDirectory = url
            processedDirectoryBookmarkData = bookmarkData
        }

        if let url, bookmarkData != nil, accessStarted {
            activeScopedAccessURLs[role] = url
        }
    }

    private func releaseScopedAccess(for role: DirectoryRole) {
        if let url = activeScopedAccessURLs.removeValue(forKey: role) {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
