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
    let openRun: (LocalProcessingRun) -> Void
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

                    pluginStrip(proxy: proxy)
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
                    Text("Local plugins · on this Mac")
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
                    revealPDF: revealPDF
                )
            }
        case .redact:
            AssistantPluginCardView(plugin: .redact) {
                if coordinator.structuredOutput != nil {
                    PresidioRedactionView(
                        coordinator: coordinator,
                        redaction: coordinator.redaction,
                        initiallyExpanded: true
                    )
                } else {
                    WorkspaceNoticeView(
                        message: "Parse first with a positioned provider — redaction reviews source-aligned blocks.",
                        systemImage: "viewfinder.circle",
                        color: .secondary
                    )
                }
            }
        case .runs:
            AssistantPluginCardView(plugin: .runs) {
                runsContent
            }
        }
    }

    private var runsContent: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            if let document {
                CurrentDocumentRowView(document: document)
                Divider()
            }

            if coordinator.recentRuns.isEmpty {
                Text("Completed parses appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.recentRuns) { run in
                    Button {
                        openRun(run)
                    } label: {
                        RunHistoryRowView(run: run)
                    }
                    .buttonStyle(.plain)
                    .disabled(coordinator.isRunning || coordinator.isInstalling)
                }
            }

            Divider()

            Button("Show Runs Folder", action: coordinator.revealRunsFolder)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(WorkspaceTheme.brand)
        }
    }

    private func pluginStrip(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: WorkspaceTheme.compactSpacing) {
            ForEach(AssistantPlugin.allCases) { plugin in
                Button {
                    let id = conversation.mount(plugin)
                    scroll(to: id, proxy: proxy)
                } label: {
                    Label(plugin.name, systemImage: plugin.systemImage)
                        .font(.callout)
                        .padding(.horizontal, WorkspaceTheme.standardSpacing)
                        .padding(.vertical, WorkspaceTheme.compactSpacing)
                        .background(
                            Color.primary.opacity(0.05),
                            in: .capsule
                        )
                        .overlay {
                            Capsule().strokeBorder(Color.primary.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
                .help(plugin.summary)
            }

            Spacer(minLength: 0)
        }
    }

    private func composer(proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .bottom, spacing: WorkspaceTheme.compactSpacing) {
            TextField("Ask for a plugin, or /help", text: $draft, axis: .vertical)
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
