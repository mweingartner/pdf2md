import Foundation

struct MonitorConfiguration: Codable, Sendable {
    var sourceDirectoryPath: String = ""
    var outputDirectoryPath: String = ""
    var processedDirectoryPath: String = ""
    var sourceDirectoryBookmarkData: Data?
    var outputDirectoryBookmarkData: Data?
    var processedDirectoryBookmarkData: Data?
    var shouldResumeMonitoring: Bool = false
    var scanIntervalSeconds: Double = 5

    var sourceDirectoryURL: URL? {
        directoryURL(for: sourceDirectoryPath)
    }

    var outputDirectoryURL: URL? {
        directoryURL(for: outputDirectoryPath)
    }

    var processedDirectoryURL: URL? {
        directoryURL(for: processedDirectoryPath)
    }

    var isComplete: Bool {
        sourceDirectoryURL != nil && outputDirectoryURL != nil && processedDirectoryURL != nil
    }

    private func directoryURL(for path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
