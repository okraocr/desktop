import SwiftUI

/// Installation and optional recognizer configuration for the Redact plugin.
/// The live task belongs to `PresidioRedactionCoordinator`, so closing and
/// reopening Plugins returns to the same progress rather than restarting it.
struct RedactPluginSetupView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @ObservedObject var redaction: PresidioRedactionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            Text("Microsoft Presidio")
                .font(.headline)
            Text("Detects PII in positioned extraction blocks. Detection and export remain explicit; the managed worker only listens on loopback.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            installationSection

            if redaction.ollamaSupported, redaction.availability.isReady {
                ollamaOptions
            }
        }
    }

    @ViewBuilder
    private var installationSection: some View {
        if redaction.isInstalling {
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                HStack {
                    Text(redaction.setupProgress?.phase.title ?? "Installing")
                        .font(.headline)
                    Spacer()
                    if let fraction = redaction.setupProgress?.fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    }
                }

                if let fraction = redaction.setupProgress?.fraction {
                    ProgressView(value: fraction)
                        .accessibilityLabel(redaction.setupProgress?.message ?? "Installing Presidio")
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(redaction.setupProgress?.message ?? "Installing Presidio")
                }

                Text(redaction.setupProgress?.message ?? redaction.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("You can close Plugins; installation will continue here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button("Cancel installation", role: .cancel, action: redaction.cancelInstallation)
                    .buttonStyle(.bordered)
            }
            .padding(WorkspaceTheme.standardSpacing)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: WorkspaceTheme.cardRadius))
        } else {
            switch redaction.availability {
            case .ready:
                WorkspaceNoticeView(
                    message: redaction.isManaged
                        ? "Microsoft Presidio is installed and ready locally."
                        : "Connected to Presidio on loopback.",
                    systemImage: "checkmark.shield.fill",
                    color: WorkspaceTheme.brand
                )
            case .simulated(let message):
                WorkspaceNoticeView(
                    message: message,
                    systemImage: "testtube.2",
                    color: .orange
                )
            case .setupRequired(let message):
                VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                    WorkspaceNoticeView(
                        message: "Setup required · \(message)",
                        systemImage: "arrow.down.circle",
                        color: .orange
                    )
                    setupSummary
                    setupError
                    Button(action: redaction.install) {
                        Text(redaction.errorMessage == nil
                            ? "Set Up Microsoft Presidio"
                            : "Retry Presidio Setup")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.isInstalling || coordinator.isRunning)
                    .accessibilityHint("Installs Presidio and its English model on this Mac")
                }
            case .unavailable(let message):
                VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                    WorkspaceNoticeView(
                        message: message,
                        systemImage: "exclamationmark.triangle.fill",
                        color: .red
                    )
                    setupError
                    if redaction.isManaged {
                        Button("Retry Presidio Setup", action: redaction.install)
                            .buttonStyle(.borderedProminent)
                            .disabled(coordinator.isInstalling || coordinator.isRunning)
                    }
                }
            }
        }
    }

    private var setupSummary: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
            Text("One-time local dependency setup")
                .font(.headline)
            Text("okraPDF creates an isolated Python environment, installs the pinned Presidio runtime and English spaCy model, then verifies the installation before marking it ready.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Network", value: "Setup only")
            LabeledContent("Runtime", value: "Local loopback")
            LabeledContent("PDF upload", value: "Never")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var setupError: some View {
        if let error = redaction.errorMessage {
            WorkspaceNoticeView(
                message: error,
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            )
        }
    }

    private var ollamaOptions: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
            Toggle("Add Presidio’s Ollama recognizer", isOn: ollamaBinding)
                .font(.callout)
                .disabled(redaction.isBusy)
            Text("Experimental and slower; it can improve names and contextual PII. Text stays on this Mac and Ollama is restricted to 127.0.0.1:11434.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if redaction.usesOllama {
                HStack {
                    Picker("Text model", selection: ollamaModelBinding) {
                        Text("Choose a local model…").tag("")
                        ForEach(coordinator.ollamaModels) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(redaction.isBusy)

                    Button("Refresh Ollama models", systemImage: "arrow.clockwise") {
                        coordinator.refreshOllamaModels()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(coordinator.isRefreshingOllamaModels || redaction.isBusy)
                }

                if let error = coordinator.ollamaErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if coordinator.ollamaModels.isEmpty {
                    Text("No installed Ollama models found. The documented lightweight default is qwen2.5:1.5b.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(WorkspaceTheme.standardSpacing)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: WorkspaceTheme.cardRadius))
    }

    private var ollamaBinding: Binding<Bool> {
        Binding(
            get: { redaction.usesOllama },
            set: { enabled in
                redaction.usesOllama = enabled
                if enabled {
                    if redaction.selectedOllamaModelName == nil {
                        redaction.selectedOllamaModelName = coordinator.ollamaModels.first?.name
                    }
                    if coordinator.ollamaModels.isEmpty {
                        coordinator.refreshOllamaModels()
                    }
                }
            }
        )
    }

    private var ollamaModelBinding: Binding<String> {
        Binding(
            get: { redaction.selectedOllamaModelName ?? "" },
            set: { redaction.selectedOllamaModelName = $0.isEmpty ? nil : $0 }
        )
    }
}
