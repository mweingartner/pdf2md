import Foundation

enum MonitorEvent: Sendable {
    case monitoringStarted
    case monitoringStopped
    case waitingForPDFs
    case converted(sourcePath: String, outputPath: String, archivedPath: String)
    case failed(sourcePath: String, message: String)
}
