import SwiftUI

/// First-run parser setup guide. Modeled on ParseBench (parsebench.ai): every
/// parser pairing is compared on the benchmark's five capability dimensions
/// with a spider graph, behind a filter combo bar. Drives the same
/// `LocalProcessingCoordinator` the Extract panel uses, so a choice made here
/// is a choice made everywhere.
struct SetupGuideView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let close: () -> Void
    let openPDF: () -> Void

    @State private var step: Step = .welcome
    @State private var filter = SetupGuideCombinationFilter()
    @State private var selectedCombinationID: String?

    private enum Step {
        case welcome
        case compare
        case setup
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome:
                welcomeStep
            case .compare:
                compareStep
            case .setup:
                setupStep
            case .done:
                doneStep
            }
        }
        .frame(minWidth: 1_020, minHeight: 680)
        .onAppear(perform: selectRecommendedCombinationIfNeeded)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: WorkspaceTheme.sectionSpacing) {
            Spacer()
            BrandMarkView(size: 64)
                .accessibilityHidden(true)
            VStack(spacing: WorkspaceTheme.compactSpacing) {
                Text("Set up local parsing")
                    .font(.largeTitle)
                    .bold()
                Text("okraPDF reads your PDF where it already lives and parses only when you ask. Everything runs on this Mac — no account, no upload.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                welcomeRow(
                    systemImage: "lock.shield",
                    title: "Local only",
                    detail: "Models run on this Mac. Only a one-time, checksum-verified model download touches the network."
                )
                welcomeRow(
                    systemImage: "hand.raised",
                    title: "Explicit by design",
                    detail: "Opening a PDF never starts a parse. You pick the parser, you press Parse."
                )
                welcomeRow(
                    systemImage: "chart.bar",
                    title: "Compared like a benchmark",
                    detail: "Pairings are scored across the five ParseBench dimensions, tuned to this Mac."
                )
            }
            .frame(maxWidth: 520)
            Spacer()
            Button("Compare parser pairings") { step = .compare }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Skip for now", action: close)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
                .frame(height: WorkspaceTheme.sectionSpacing)
        }
        .padding(WorkspaceTheme.panelPadding * 2)
    }

    private var compareStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                title: "Choose your parser pairing",
                subtitle: coordinator.doctorDiagnosis.hostSummary
            )
            filterBar
            Divider()
            HStack(spacing: 0) {
                combinationList
                    .frame(width: 320)
                Divider()
                combinationDetail
            }
            Divider()
            footer(
                backTitle: "Back",
                backAction: { step = .welcome }
            )
        }
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                title: "Set up \(selectedCombination?.title ?? coordinator.selectedDescriptor.name)",
                subtitle: selectedCombination?.pairingSummary ?? ""
            )
            ScrollView {
                VStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
                    if selectedUsesOllama {
                        OllamaIntegrationView(coordinator: coordinator)
                        Text("Install a vision model in Ollama, refresh, and it appears as a pairing. okraPDF talks to Ollama over its localhost HTTP API only.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProviderSetupView(coordinator: coordinator)
                    }

                    if coordinator.selectedAvailability.isReady {
                        WorkspaceNoticeView(
                            message: "\(coordinator.selectedDescriptor.name) is ready.",
                            systemImage: "checkmark.circle.fill",
                            color: WorkspaceTheme.brand
                        )
                    } else if selectedUsesOllama == false, coordinator.setupProgress == nil {
                        Text(coordinator.selectedAvailability.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(WorkspaceTheme.panelPadding * 2)
            }
            Divider()
            footer(
                backTitle: "Back to pairings",
                backAction: { step = .compare },
                continueTitle: "Continue",
                continueEnabled: coordinator.selectedAvailability.isReady,
                continueAction: { step = .done }
            )
        }
    }

    private var doneStep: some View {
        VStack(spacing: WorkspaceTheme.sectionSpacing) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(WorkspaceTheme.brand)
                .accessibilityHidden(true)
            VStack(spacing: WorkspaceTheme.compactSpacing) {
                Text("You're all set")
                    .font(.largeTitle)
                    .bold()
                if let combination = selectedCombination {
                    Text("\(combination.title) is your local parser. Open a PDF, then press Parse in the Extract panel — the original file never moves and parsing never starts on its own.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
            }
            HStack(spacing: WorkspaceTheme.standardSpacing) {
                Button("Open a PDF…") {
                    close()
                    openPDF()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Start reading", action: close)
                    .controlSize(.large)
            }
            Spacer()
            Button("Change parser", action: { step = .compare })
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
                .frame(height: WorkspaceTheme.sectionSpacing)
        }
        .padding(WorkspaceTheme.panelPadding * 2)
    }

    // MARK: - Compare step pieces

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
            HStack(spacing: WorkspaceTheme.compactSpacing) {
                chip(
                    "On-device only",
                    systemImage: "desktopcomputer",
                    isActive: filter.onDeviceOnly
                ) { filter.onDeviceOnly.toggle() }
                chip(
                    "Zero setup",
                    systemImage: "bolt",
                    isActive: filter.zeroSetupOnly
                ) { filter.zeroSetupOnly.toggle() }
                chip(
                    "Recommended",
                    systemImage: "star.fill",
                    isActive: filter.recommendedOnly
                ) { filter.recommendedOnly.toggle() }

                Divider()
                    .frame(height: 16)

                ForEach(SetupGuideDeliveryKind.allCases, id: \.self) { kind in
                    chip(
                        kind.title,
                        systemImage: nil,
                        isActive: filter.deliveryKinds.contains(kind)
                    ) { filter.toggleDeliveryKind(kind) }
                }

                Spacer()

                if filter.isActive {
                    Button("Clear filters") { filter.reset() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: WorkspaceTheme.compactSpacing) {
                Text("Needs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                capabilityChip(.tables, title: "Tables")
                capabilityChip(.charts, title: "Charts")
                capabilityChip(.formulas, title: "Formulas")
                capabilityChip(.boundingBoxes, title: "Bounding boxes")
            }
        }
        .padding(.horizontal, WorkspaceTheme.panelPadding)
        .padding(.vertical, WorkspaceTheme.standardSpacing)
    }

    private var combinationList: some View {
        ScrollView {
            LazyVStack(spacing: WorkspaceTheme.compactSpacing) {
                if filteredCombinations.isEmpty {
                    VStack(spacing: WorkspaceTheme.compactSpacing) {
                        Text("No pairings match these filters.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Clear filters") { filter.reset() }
                            .buttonStyle(.link)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, WorkspaceTheme.sectionSpacing * 2)
                } else {
                    ForEach(filteredCombinations) { combination in
                        combinationRow(combination)
                    }
                }
            }
            .padding(WorkspaceTheme.standardSpacing)
        }
        .background(.quaternary.opacity(0.12))
    }

    private func combinationRow(_ combination: SetupGuideCombination) -> some View {
        Button {
            selectedCombinationID = combination.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(combination.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(combination.overallScore, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(combination.pairingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: WorkspaceTheme.compactSpacing) {
                    statusView(for: combination)
                    ForEach(combination.badges, id: \.self) { badge in
                        Text(badge.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WorkspaceTheme.brand.opacity(0.14), in: Capsule())
                    }
                }
            }
            .padding(WorkspaceTheme.standardSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                combination.id == selectedCombinationID
                    ? WorkspaceTheme.brand.opacity(0.12)
                    : Color.clear,
                in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
            )
            .overlay {
                if combination.id == selectedCombinationID {
                    RoundedRectangle(cornerRadius: WorkspaceTheme.cardRadius)
                        .stroke(WorkspaceTheme.brand.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(combination.verdictTier == .unsupported)
        .opacity(combination.verdictTier == .unsupported ? 0.45 : 1)
        .accessibilityHint(combination.verdictTier == .unsupported
            ? "Not supported on this Mac"
            : "Show this pairing in the comparison chart")
    }

    private var combinationDetail: some View {
        ScrollView {
            if let combination = selectedCombination {
                VStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(combination.title)
                            .font(.title2)
                            .bold()
                        Text(combination.pairingSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    RadarChartView(
                        axes: ParseBenchDimension.allCases,
                        series: chartSeries(for: combination)
                    )
                    .frame(maxWidth: 380)
                    .frame(maxWidth: .infinity, alignment: .center)

                    legend(for: combination)

                    VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                        ForEach(ParseBenchDimension.allCases, id: \.self) { dimension in
                            dimensionRow(dimension, combination: combination)
                        }
                    }

                    verdictNotes(for: combination)

                    disclaimer

                    Button(action: { useCombination(combination) }) {
                        Text(ctaTitle(for: combination))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(combination.verdictTier == .unsupported)
                }
                .padding(WorkspaceTheme.panelPadding * 1.5)
            } else {
                Text("Pick a pairing on the left to compare it on the ParseBench dimensions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(WorkspaceTheme.panelPadding * 2)
            }
        }
    }

    private func chartSeries(
        for combination: SetupGuideCombination
    ) -> [RadarChartSeries] {
        var series = [
            RadarChartSeries(
                name: combination.title,
                color: WorkspaceTheme.brand,
                values: ParseBenchDimension.allCases.map(combination.score(for:))
            ),
        ]
        if let recommended = recommendedCombination, recommended.id != combination.id {
            series.append(
                RadarChartSeries(
                    name: "\(recommended.title) (recommended)",
                    color: .secondary,
                    values: ParseBenchDimension.allCases.map(recommended.score(for:))
                )
            )
        }
        return series
    }

    private func legend(for combination: SetupGuideCombination) -> some View {
        HStack(spacing: WorkspaceTheme.sectionSpacing) {
            ForEach(chartSeries(for: combination)) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                    Text(item.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func dimensionRow(
        _ dimension: ParseBenchDimension,
        combination: SetupGuideCombination
    ) -> some View {
        let score = combination.score(for: dimension)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(dimension.title)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(score, format: .percent.precision(.fractionLength(0)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(WorkspaceTheme.brand)
                        .frame(width: proxy.size.width * score)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text(dimension.summary)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dimension.title): \(Int((score * 100).rounded())) percent. \(dimension.summary)")
    }

    private func verdictNotes(for combination: SetupGuideCombination) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ppm = combination.estimatedPagesPerMinute {
                Label(
                    "Estimated ~\(ppm, format: .number.precision(.fractionLength(1))) pages/min on this Mac",
                    systemImage: "gauge.with.dots.needle.33percent"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let verdict = coordinator.doctorDiagnosis.verdict(for: combination.providerID),
               let reason = verdict.reasons.first {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Relative estimates on the five ParseBench capability dimensions, seeded from public benchmark results and each parser's declared capabilities — not measured on this Mac. dots.mocr scores 55.8 overall on the public ParseBench leaderboard.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: WorkspaceTheme.standardSpacing) {
                Link("parsebench.ai", destination: URL(string: "https://parsebench.ai")!)
                Link("Hugging Face dataset", destination: URL(string: "https://huggingface.co/datasets/llamaindex/ParseBench")!)
            }
            .font(.caption)
        }
    }

    // MARK: - Shared chrome

    private func header(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2)
                .bold()
            Spacer()
            if subtitle.isEmpty == false {
                Label(subtitle, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, WorkspaceTheme.panelPadding)
        .padding(.vertical, WorkspaceTheme.standardSpacing)
    }

    private func footer(
        backTitle: String,
        backAction: @escaping () -> Void,
        continueTitle: String? = nil,
        continueEnabled: Bool = true,
        continueAction: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Button(backTitle, action: backAction)
            Spacer()
            Button("Not now", action: close)
                .foregroundStyle(.secondary)
            if let continueTitle, let continueAction {
                Button(continueTitle, action: continueAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(continueEnabled == false)
            }
        }
        .padding(.horizontal, WorkspaceTheme.panelPadding)
        .padding(.vertical, WorkspaceTheme.standardSpacing)
    }

    private func chip(
        _ title: String,
        systemImage: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                Text(title)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isActive ? WorkspaceTheme.brand.opacity(0.16) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isActive ? WorkspaceTheme.brand.opacity(0.7) : Color.clear, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func capabilityChip(
        _ capability: LocalParserCapability,
        title: String
    ) -> some View {
        chip(
            title,
            systemImage: nil,
            isActive: filter.requiredCapabilities.contains(capability)
        ) { filter.toggleCapability(capability) }
    }

    private func welcomeRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(WorkspaceTheme.brand)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusView(for combination: SetupGuideCombination) -> some View {
        let (text, color): (String, Color) = {
            switch combination.availability {
            case .ready:
                return ("Ready offline", WorkspaceTheme.brand)
            case .simulated:
                return ("Simulated", .orange)
            case .setupRequired:
                if let bytes = combination.downloadSizeBytes {
                    return ("\(bytes.formatted(.byteCount(style: .file))) download", .secondary)
                }
                return ("Setup required", .secondary)
            case .unavailable:
                return ("Not supported on this Mac", .red)
            }
        }()
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Combination state

    private var combinations: [SetupGuideCombination] {
        SetupGuideCombinationCatalog.combinations(
            descriptors: coordinator.descriptors,
            availabilityByProvider: coordinator.availabilityByProvider,
            diagnosis: coordinator.doctorDiagnosis,
            ollamaVisionModels: coordinator.ollamaVisionModels
        )
    }

    private var filteredCombinations: [SetupGuideCombination] {
        combinations.filter(filter.matches)
    }

    private var selectedCombination: SetupGuideCombination? {
        if let selectedCombinationID,
           let match = combinations.first(where: { $0.id == selectedCombinationID }) {
            return match
        }
        return combinations.first
    }

    private var recommendedCombination: SetupGuideCombination? {
        guard let recommendedID = coordinator.doctorDiagnosis.recommendedProviderID else {
            return nil
        }
        let candidates = combinations.filter { $0.providerID == recommendedID }
        if let selectedModel = coordinator.selectedOllamaModelName,
           let match = candidates.first(where: { $0.ollamaModelName == selectedModel }) {
            return match
        }
        return candidates.first
    }

    private var selectedUsesOllama: Bool {
        let providerID = selectedCombination?.providerID ?? coordinator.selectedProviderID
        return providerID == .ollama || providerID == .hybridAuto
    }

    private func selectRecommendedCombinationIfNeeded() {
        guard selectedCombinationID == nil else { return }
        if let stored = combinations.first(where: {
            $0.providerID == coordinator.selectedProviderID
                && ($0.ollamaModelName == nil
                    || $0.ollamaModelName == coordinator.selectedOllamaModelName)
        }) {
            selectedCombinationID = stored.id
        } else {
            selectedCombinationID = recommendedCombination?.id ?? combinations.first?.id
        }
    }

    private func useCombination(_ combination: SetupGuideCombination) {
        if let modelName = combination.ollamaModelName {
            coordinator.selectedOllamaModelName = modelName
        }
        coordinator.selectedProviderID = combination.providerID
        if combination.availability.isReady {
            step = .done
        } else {
            step = .setup
        }
    }

    private func ctaTitle(for combination: SetupGuideCombination) -> String {
        switch combination.availability {
        case .ready, .simulated:
            return "Use \(combination.title)"
        case .setupRequired:
            return combination.downloadSizeBytes == nil
                ? "Set up \(combination.title)"
                : "Download & use \(combination.title)"
        case .unavailable:
            return "Not supported on this Mac"
        }
    }
}
