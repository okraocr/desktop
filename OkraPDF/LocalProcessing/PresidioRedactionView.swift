import SwiftUI

struct PresidioRedactionView: View {
    @ObservedObject var redaction: PresidioRedactionCoordinator
    let showPlugin: () -> Void
    @State private var isExpanded: Bool

    init(
        redaction: PresidioRedactionCoordinator,
        showPlugin: @escaping () -> Void,
        initiallyExpanded: Bool = false
    ) {
        _redaction = ObservedObject(wrappedValue: redaction)
        self.showPlugin = showPlugin
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
            VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                WorkspaceNoticeView(
                    message: redaction.isManaged
                        ? "Microsoft Presidio is ready locally."
                        : "Connected to Presidio on loopback.",
                    systemImage: "checkmark.shield.fill",
                    color: WorkspaceTheme.brand
                )
                Button("Plugin Settings", action: showPlugin)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Opens Presidio configuration in Plugins")
            }
        case .simulated(let message):
            VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                WorkspaceNoticeView(
                    message: message,
                    systemImage: "testtube.2",
                    color: .orange
                )
                Button("Plugin Settings", action: showPlugin)
                    .buttonStyle(.bordered)
            }
        case .setupRequired(let message):
            VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                WorkspaceNoticeView(
                    message: redaction.isInstalling
                        ? "Presidio is being installed in Plugins."
                        : "Setup required · \(message)",
                    systemImage: "arrow.down.circle",
                    color: .orange
                )
                Button(action: showPlugin) {
                    Text(redaction.isInstalling ? "View Installation" : "Open Redact Plugin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens Redact under Plugins where Presidio setup is managed")
            }
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                WorkspaceNoticeView(
                    message: message,
                    systemImage: "exclamationmark.triangle.fill",
                    color: .red
                )
                Button("Open Redact Plugin", action: showPlugin)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Opens Redact under Plugins for Presidio status and configuration")
            }
        }
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
}
