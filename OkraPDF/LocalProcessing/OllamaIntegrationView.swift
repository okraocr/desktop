import SwiftUI

struct OllamaIntegrationView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ollama integration")
                        .font(.headline)
                    Text("http://127.0.0.1:11434")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh models", action: coordinator.refreshOllamaModels)
                    .disabled(coordinator.isRefreshingOllamaModels)
            }

            if coordinator.isRefreshingOllamaModels {
                HStack(spacing: WorkspaceTheme.compactSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Asking Ollama for installed models…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let error = coordinator.ollamaErrorMessage {
                WorkspaceNoticeView(
                    message: error,
                    systemImage: "exclamationmark.triangle.fill",
                    color: .red
                )
            } else if coordinator.ollamaVisionModels.isEmpty {
                WorkspaceNoticeView(
                    message: "No installed models report vision capability. Add a vision model in Ollama, then refresh.",
                    systemImage: "eye.slash",
                    color: .secondary
                )
            } else {
                Picker("Vision model", selection: selectedModelBinding) {
                    ForEach(coordinator.ollamaVisionModels) { model in
                        Text(modelLabel(model))
                            .tag(model.name)
                    }
                }
                .pickerStyle(.menu)

                if let model = selectedModel {
                    LabeledContent("Managed by Ollama") {
                        Text(model.size, format: .byteCount(style: .file))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Text("Okra uses Ollama’s HTTP API to list models and parse pages. It does not inspect model folders, run the Ollama CLI, or download Ollama models.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WorkspaceTheme.standardSpacing)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: WorkspaceTheme.cardRadius))
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: {
                coordinator.selectedOllamaModelName
                    ?? coordinator.ollamaVisionModels.first?.name
                    ?? ""
            },
            set: { coordinator.selectedOllamaModelName = $0 }
        )
    }

    private var selectedModel: OllamaModel? {
        guard let selected = coordinator.selectedOllamaModelName else { return nil }
        return coordinator.ollamaVisionModels.first { $0.name == selected }
    }

    private func modelLabel(_ model: OllamaModel) -> String {
        [model.name, model.parameterSize, model.quantizationLevel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
