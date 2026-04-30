import SwiftUI

struct MonitorDashboardView: View {
    @Bindable var model: PDF2MDAppModel
    private let panelWidth: CGFloat = 460
    private let panelHeight: CGFloat = 560

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                configurationSection
                actionSection
                activitySection
                footerSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Label("PDF2MD Monitor", systemImage: model.isMonitoring ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(model.isMonitoring ? "Active" : "Idle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(model.isMonitoring ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15))
                    .foregroundStyle(model.isMonitoring ? Color.green : Color.secondary)
                    .clipShape(Capsule())
            }

            Text(model.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders")
                .font(.headline)

            directorySection(
                title: "Watch for PDFs",
                url: model.sourceDirectory,
                actionTitle: "Choose Source",
                chooseAction: model.chooseSourceDirectory,
                revealAction: { model.reveal(model.sourceDirectory) }
            )

            directorySection(
                title: "Write Markdown To",
                url: model.outputDirectory,
                actionTitle: "Choose Output",
                chooseAction: model.chooseOutputDirectory,
                revealAction: { model.reveal(model.outputDirectory) }
            )

            directorySection(
                title: "Move Processed PDFs To",
                url: model.processedDirectory,
                actionTitle: "Choose Processed",
                chooseAction: model.chooseProcessedDirectory,
                revealAction: { model.reveal(model.processedDirectory) }
            )

            if let configurationError = model.configurationError {
                Text(configurationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Control")
                .font(.headline)

            HStack {
                Button(model.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                    model.toggleMonitoring()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isMonitoring && !model.canStartMonitoring)

                Button("Scan Now") {
                    model.scanNow()
                }
                .disabled(!model.canStartMonitoring)
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.headline)

            if model.recentEvents.isEmpty {
                Text("No activity yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.recentEvents) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.message)
                                .font(.footnote)
                                .foregroundStyle(entry.isError ? Color.red : Color.primary)
                                .textSelection(.enabled)

                            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button("Quit PDF2MD") {
                model.quitApp()
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("Runs in the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func directorySection(
        title: String,
        url: URL?,
        actionTitle: String,
        chooseAction: @escaping () -> Void,
        revealAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))

            Text(url?.path ?? "No folder selected")
                .font(.footnote)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button(actionTitle, action: chooseAction)
                Button("Reveal", action: revealAction)
                    .disabled(url == nil)
            }
            .buttonStyle(.bordered)
        }
    }
}
