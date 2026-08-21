import SwiftUI

/// The trailing assistant panel: a session timeline where local features
/// mount as plugin cards, with a composer that routes slash commands and
/// plain words through the deterministic on-device router.
struct AssistantPanelView: View {
    let document: LocalPDFDocument?
    let importError: String?
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @ObservedObject var conversation: AssistantConversation
    let parse: () -> Void
    let revealPDF: () -> Void
    let openPDF: () -> Void
    /// Opens the selected plugin in the leading navigation.
    let showPlugin: (AssistantPlugin) -> Void
    /// Opens workspace activity in the leading navigation.
    let showActivity: (WorkspaceActivity) -> Void
    let dismiss: () -> Void

    @State private var draft = ""

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                timeline

                Divider()

                VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                    if let importError {
                        WorkspaceNoticeView(
                            message: importError,
                            systemImage: "exclamationmark.triangle.fill",
                            color: .red
                        )
                    }

                    composer(proxy: proxy)
                }
                .padding(WorkspaceTheme.panelPadding)
            }
            .onChange(of: conversation.entries.count) { _ in
                scrollToLatest(proxy: proxy)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .background(.bar)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
                VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                    Text("Assistant")
                        .font(.headline)
                    Text("Local tools and activity · on this Mac")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Hide assistant", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Hide assistant")
            }
            .padding(WorkspaceTheme.panelPadding)

            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
                ForEach(conversation.entries) { entry in
                    entryView(entry)
                        .id(entry.id)
                }
            }
            .padding(WorkspaceTheme.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func entryView(_ entry: AssistantEntry) -> some View {
        switch entry.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 40)
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, WorkspaceTheme.standardSpacing)
                    .padding(.vertical, WorkspaceTheme.compactSpacing + 2)
                    .background(
                        WorkspaceTheme.brand.opacity(0.14),
                        in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(text)")
        case .assistant(let text):
            Text(text)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, WorkspaceTheme.standardSpacing)
                .padding(.vertical, WorkspaceTheme.compactSpacing + 2)
                .background(
                    Color.primary.opacity(0.05),
                    in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
                )
                .accessibilityLabel("Assistant: \(text)")
        case .plugin(let plugin):
            pluginCard(plugin)
        case .activity(let activity):
            activityCard(activity)
        }
    }

    @ViewBuilder
    private func pluginCard(_ plugin: AssistantPlugin) -> some View {
        switch plugin {
        case .extract:
            AssistantPluginCardView(plugin: .extract) {
                LocalExtractionView(
                    document: document,
                    coordinator: coordinator,
                    parse: parse,
                    revealPDF: revealPDF,
                    showPlugin: { showPlugin(.extract) }
                )
            }
        case .redact:
            AssistantPluginCardView(plugin: .redact) {
                if coordinator.structuredOutput != nil {
                    PresidioRedactionView(
                        redaction: coordinator.redaction,
                        showPlugin: { showPlugin(.redact) },
                        initiallyExpanded: true
                    )
                } else {
                    VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                        WorkspaceNoticeView(
                            message: "Parse first with a positioned provider — redaction reviews source-aligned blocks.",
                            systemImage: "viewfinder.circle",
                            color: .secondary
                        )
                        Button("Open Redact Plugin") {
                            showPlugin(.redact)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Opens Presidio installation and configuration in Plugins")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activityCard(_ activity: WorkspaceActivity) -> some View {
        switch activity {
        case .runs:
            AssistantActivityCardView(activity: .runs) {
                runsContent
            }
        }
    }

    private var runsContent: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            if coordinator.recentRuns.isEmpty {
                Text("Completed parses appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let count = coordinator.recentRuns.count
                Text(count == 1 ? "1 recent local run" : "\(count) recent local runs")
                    .font(.callout)
                Text("Open Activity to browse runs, reopen outputs, or reveal the Runs folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showActivity(.runs)
            } label: {
                Text("Open Runs")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Opens Runs under Activity in the left navigation")
        }
    }

    private func composer(proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .bottom, spacing: WorkspaceTheme.compactSpacing) {
            TextField("Ask for a tool, or /help", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit {
                    sendDraft(proxy: proxy)
                }

            Button("Send", systemImage: "arrow.up.circle.fill") {
                sendDraft(proxy: proxy)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.title2)
            .foregroundStyle(draftIsEmpty ? Color.secondary : WorkspaceTheme.brand)
            .disabled(draftIsEmpty)
        }
        .padding(WorkspaceTheme.standardSpacing)
        .background(
            Color.primary.opacity(0.05),
            in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
        )
    }

    private var draftIsEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft(proxy: ScrollViewProxy) {
        guard draftIsEmpty == false else { return }
        let text = draft
        draft = ""
        if let id = conversation.send(
            text,
            documentIsOpen: document != nil,
            openPDF: openPDF
        ) {
            scroll(to: id, proxy: proxy)
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let last = conversation.entries.last else { return }
        scroll(to: last.id, proxy: proxy)
    }

    private func scroll(to id: Int, proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}
