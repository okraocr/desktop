import SwiftUI

struct ProviderStatusView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
            Label(
                coordinator.selectedAvailability.message,
                systemImage: coordinator.selectedAvailability.isReady
                    ? "checkmark.circle.fill"
                    : "circle.dashed"
            )
            .font(.headline)
            .foregroundStyle(coordinator.selectedAvailability.isReady ? WorkspaceTheme.brand : .secondary)

            Text(coordinator.selectedDescriptor.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let verdict = coordinator.doctorVerdict(for: coordinator.selectedProviderID),
               let headline = verdict.reasons.first {
                Text(headline)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let setupNote = coordinator.selectedDescriptor.setupNote {
                Text(setupNote)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if coordinator.selectedAvailability.isSimulated {
                WorkspaceNoticeView(
                    message: "Simulation validates rendering, the bundled worker, offline flags, Markdown, and run persistence. It does not load or evaluate model weights.",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
        }
    }
}
