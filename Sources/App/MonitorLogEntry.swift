import Foundation

struct MonitorLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let isError: Bool
}
