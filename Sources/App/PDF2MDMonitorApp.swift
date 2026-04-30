import SwiftUI

@main
struct PDF2MDMonitorApp: App {
    @State private var model = PDF2MDAppModel()

    var body: some Scene {
        MenuBarExtra("PDF2MD", systemImage: model.isMonitoring ? "doc.text.viewfinder" : "doc.text") {
            MonitorDashboardView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
