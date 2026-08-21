import SwiftUI

struct AssistantPluginCardView<Content: View>: View {
    let plugin: AssistantPlugin
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
                Image(systemName: plugin.systemImage)
                    .foregroundStyle(WorkspaceTheme.brand)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.headline)
                    Text(plugin.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Divider()

            content
        }
        .padding(WorkspaceTheme.standardSpacing)
        .background(
            Color.primary.opacity(0.035),
            in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WorkspaceTheme.cardRadius)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(plugin.name) plugin")
    }
}

struct AssistantActivityCardView<Content: View>: View {
    let activity: WorkspaceActivity
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
                Image(systemName: activity.systemImage)
                    .foregroundStyle(WorkspaceTheme.brand)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name)
                        .font(.headline)
                    Text(activity.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Divider()
            content
        }
        .padding(WorkspaceTheme.standardSpacing)
        .background(
            Color.primary.opacity(0.035),
            in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WorkspaceTheme.cardRadius)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(activity.name) activity")
    }
}
