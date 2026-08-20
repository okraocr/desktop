import SwiftUI

struct PresidioRedactionView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @ObservedObject var redaction: PresidioRedactionCoordinator
    @State private var isExpanded: Bool

    init(
        coordinator: LocalProcessingCoordinator,
        redaction: PresidioRedactionCoordinator,
        initiallyExpanded: Bool = false
    ) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
        _redaction = ObservedObject(wrappedValue: redaction)
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                    Text("Presidio checks positioned extraction blocks only after you ask it to. Review every candidate; the source PDF is never changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    availabilityView

                    if redaction.ollamaSupported {
                        ollamaOptions
                    }

                    if redaction.hasPositionedBlocks == false {
                        WorkspaceNoticeView(
                            message: "This run has no source-aligned blocks. Parse with Apple Vision, Dots OCR, Baidu Unlimited-OCR, Chandra OCR 2, or Auto before detecting redaction boxes.",
                            systemImage: "viewfinder.circle",
                            color: .orange
                        )
                    }

                    Button(action: redaction.detect) {
                        HStack {
                            if redaction.isDetecting {
                                ProgressView().controlSize(.small)
                            }
                            Text(redaction.detection == nil ? "Detect PII" : "Detect Again")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(redaction.canDetect == false)
                    .accessibilityHint("Analyzes positioned extraction text locally with Microsoft Presidio")

                    if let error = redaction.errorMessage {
                        WorkspaceNoticeView(
                            message: error,
                            systemImage: "exclamationmark.triangle.fill",
                            color: .red
                        )
                    } else {
                        Text(redaction.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let detection = redaction.detection {
                        candidateReview(detection)
                    }
                }
                .padding(.top, WorkspaceTheme.compactSpacing)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redact PII locally")
                        .font(.headline)
                    Text("Presidio · review · irreversible export")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var availabilityView: some View {
        switch redaction.availability {
        case .ready:
            WorkspaceNoticeView(
                message: redaction.isManaged
                    ? "Microsoft Presidio is ready locally."
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
            VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                WorkspaceNoticeView(
                    message: "Setup required · \(message)",
                    systemImage: "arrow.down.circle",
                    color: .orange
                )
                Button(action: redaction.install) {
                    HStack {
                        if redaction.isInstalling {
                            ProgressView().controlSize(.small)
                        }
                        Text(redaction.isInstalling ? "Setting Up Presidio…" : "Set Up Presidio Locally")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(redaction.isInstalling)
            }
        case .unavailable(let message):
            WorkspaceNoticeView(
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            )
        }
    }

    private var ollamaOptions: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
            Toggle("Add Presidio’s Ollama recognizer", isOn: ollamaBinding)
                .font(.callout)
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

                    Button("Refresh Ollama models", systemImage: "arrow.clockwise") {
                        coordinator.refreshOllamaModels()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(coordinator.isRefreshingOllamaModels)
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

    private func candidateReview(_ detection: RedactionDetection) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            HStack {
                Text("\(detection.stats.total) candidates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(redaction.approvedBoxes.count) approved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if detection.boxes.isEmpty {
                Text("No PII candidates were found above the confidence threshold.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(WorkspaceTheme.standardSpacing)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.2), in: .rect(cornerRadius: WorkspaceTheme.cardRadius))
            } else {
                ForEach(detection.boxes) { box in
                    candidateRow(box)
                }

                Text("Export rasterizes each affected page before drawing approved black boxes. This removes hidden text but turns affected pages into images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: redaction.export) {
                    HStack {
                        if redaction.isExporting {
                            ProgressView().controlSize(.small)
                        }
                        Text("Export Redacted PDF…")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .disabled(redaction.approvedBoxes.isEmpty || redaction.isBusy)
            }
        }
    }

    private func candidateRow(_ box: RedactionBox) -> some View {
        let approved = redaction.approvedBoxIDs.contains(box.id)
        let highlighted = redaction.selectedBoxID == box.id || redaction.hoveredBoxID == box.id
        return HStack(alignment: .top, spacing: WorkspaceTheme.compactSpacing) {
            Toggle(
                "Approve \(box.type) redaction",
                isOn: Binding(
                    get: { redaction.approvedBoxIDs.contains(box.id) },
                    set: { redaction.setApproved($0, for: box.id) }
                )
            )
            .labelsHidden()

            Button {
                redaction.selectBox(box.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(box.type.replacingOccurrences(of: "_", with: " "))
                            .font(.caption.bold())
                        Spacer()
                        Text("p. \(box.page) · \(Int((box.score * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(box.text.isEmpty ? "Detected value" : box.text)
                        .font(.callout)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(box.source)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(approved == false)
        }
        .padding(WorkspaceTheme.compactSpacing)
        .background(
            highlighted ? Color.orange.opacity(0.14) : Color.secondary.opacity(approved ? 0.07 : 0.03),
            in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
        )
        .opacity(approved ? 1 : 0.55)
        .onHover { redaction.hoverBox(box.id, isHovering: $0) }
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
