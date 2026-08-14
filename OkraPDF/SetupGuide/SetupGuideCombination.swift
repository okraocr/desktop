import Foundation

/// The five capability dimensions ParseBench (parsebench.ai, arXiv 2604.08538)
/// scores every parser on. The setup guide uses the same axes so combinations
/// are comparable against the public leaderboard shape.
enum ParseBenchDimension: String, CaseIterable, Codable, Sendable {
    case tables
    case charts
    case contentFaithfulness
    case semanticFormatting
    case visualGrounding

    var title: String {
        switch self {
        case .tables: "Tables"
        case .charts: "Charts"
        case .contentFaithfulness: "Content faithfulness"
        case .semanticFormatting: "Semantic formatting"
        case .visualGrounding: "Visual grounding"
        }
    }

    var summary: String {
        switch self {
        case .tables: "Merged cells and header structure survive extraction."
        case .charts: "Chart values, series, and labels become usable data."
        case .contentFaithfulness: "Words and numbers match the page exactly."
        case .semanticFormatting: "Headings, lists, and reading order stay meaningful."
        case .visualGrounding: "Output blocks map back to their location on the page."
        }
    }
}

/// Who owns the model in a pairing. Everything runs on this Mac; the kinds
/// describe the delivery boundary, mirroring ParseBench's method categories.
enum SetupGuideDeliveryKind: String, CaseIterable, Codable, Sendable {
    /// Built into macOS. No model download, no setup.
    case system
    /// A pinned model okraPDF downloads, verifies, and runs on-device.
    case managedModel
    /// A vision model your local Ollama runtime owns and serves.
    case ollama
    /// Native PDF text paired with an Ollama-served VLM fallback.
    case hybrid

    var title: String {
        switch self {
        case .system: "macOS built-in"
        case .managedModel: "On-device model"
        case .ollama: "Ollama pairing"
        case .hybrid: "Hybrid pairing"
        }
    }
}

/// One selectable parser pairing, in the ParseBench sense: a parsing pipeline
/// paired with the model that powers it. Non-Ollama providers form exactly one
/// combination; Ollama-backed providers form one per installed vision model.
struct SetupGuideCombination: Identifiable, Equatable {
    let providerID: LocalProviderID
    /// Set for Ollama-backed pairings; nil for system and managed providers.
    let ollamaModelName: String?
    let title: String
    /// What is paired with what, e.g. "Native text layer × Ollama vision model".
    let pairingSummary: String
    let deliveryKind: SetupGuideDeliveryKind
    /// Relative capability per ParseBench dimension, 0…1.
    let scores: [ParseBenchDimension: Double]
    let capabilities: Set<LocalParserCapability>
    let availability: LocalProviderAvailability
    let badges: [LocalParserBadge]
    let verdictTier: LocalParserVerdictTier
    let estimatedPagesPerMinute: Double?
    let downloadSizeBytes: Int64?

    var id: String {
        providerID.rawValue + (ollamaModelName.map { ":\($0)" } ?? "")
    }

    var requiresSetup: Bool {
        availability.isReady == false
    }

    var isRecommended: Bool {
        badges.contains(.recommendedForThisMac)
    }

    var overallScore: Double {
        ParseBenchDimension.allCases.reduce(0.0) { $0 + (scores[$1] ?? 0) }
            / Double(ParseBenchDimension.allCases.count)
    }

    func score(for dimension: ParseBenchDimension) -> Double {
        scores[dimension] ?? 0
    }
}

/// Seeded relative capability estimates, 0…1 per ParseBench dimension.
/// Anchors: dots.mocr publishes a ParseBench overall of 55.8
/// (huggingface.co/datasets/llamaindex/ParseBench) and 87.5 EN on
/// OmniDocBench (internal/research/ocr-sota-2026-04.md); Apple Vision emits
/// text only. These guide a first-run choice; they are not measured on-device.
enum SetupGuideScoreCatalog {
    static func scores(
        for providerID: LocalProviderID,
        ollamaModelName: String?
    ) -> [ParseBenchDimension: Double] {
        switch providerID {
        case .appleVision:
            return [
                .tables: 0.12,
                .charts: 0.08,
                .contentFaithfulness: 0.72,
                .semanticFormatting: 0.30,
                .visualGrounding: 0.0,
            ]
        case .dotsOCR:
            return [
                .tables: 0.78,
                .charts: 0.62,
                .contentFaithfulness: 0.80,
                .semanticFormatting: 0.72,
                .visualGrounding: 0.66,
            ]
        case .chandraOCR2:
            // ParseBench chandra-ocr-2: 70.1 overall, 89.2 tables, 65.1 charts —
            // the strongest managed row on the public leaderboard.
            return [
                .tables: 0.85,
                .charts: 0.62,
                .contentFaithfulness: 0.82,
                .semanticFormatting: 0.76,
                .visualGrounding: 0.72,
            ]
        case .unlimitedOCR:
            return [
                .tables: 0.52,
                .charts: 0.42,
                .contentFaithfulness: 0.70,
                .semanticFormatting: 0.55,
                .visualGrounding: 0.48,
            ]
        case .ollama:
            return ollamaScores(modelName: ollamaModelName)
        case .hybridAuto:
            var scores = ollamaScores(modelName: ollamaModelName)
            // Digital pages bypass the VLM entirely, so text is exact there.
            scores[.contentFaithfulness] = max(scores[.contentFaithfulness] ?? 0, 0.88)
            return scores
        }
    }

    /// Generic local vision-model estimates. Larger served models trend
    /// higher on structure; grounding stays low because the output adapter
    /// returns Markdown without boxes.
    private static func ollamaScores(
        modelName: String?
    ) -> [ParseBenchDimension: Double] {
        let structureBump = modelName.map(structureBump(for:)) ?? 0.0
        return [
            .tables: 0.45 + structureBump,
            .charts: 0.38 + structureBump,
            .contentFaithfulness: 0.64 + structureBump,
            .semanticFormatting: 0.45 + structureBump,
            .visualGrounding: 0.18,
        ]
    }

    private static func structureBump(for modelName: String) -> Double {
        guard let match = modelName.range(
            of: #"(\d+)\s*[bB]"#,
            options: .regularExpression
        ) else { return 0 }
        let digits = modelName[match].drop(while: { $0.isNumber == false })
            .filter(\.isNumber)
        guard let billions = Double(digits) else { return 0 }
        if billions >= 20 { return 0.15 }
        if billions >= 8 { return 0.08 }
        return 0.0
    }
}

/// Builds the combination list from live coordinator state. Pure and
/// deterministic so the wizard and tests share one code path.
enum SetupGuideCombinationCatalog {
    static func combinations(
        descriptors: [LocalProviderDescriptor],
        availabilityByProvider: [LocalProviderID: LocalProviderAvailability],
        diagnosis: LocalParserDiagnosis,
        ollamaVisionModels: [OllamaModel]
    ) -> [SetupGuideCombination] {
        descriptors.flatMap { descriptor -> [SetupGuideCombination] in
            let availability = availabilityByProvider[descriptor.id]
                ?? .unavailable("Unavailable")
            let verdict = diagnosis.verdict(for: descriptor.id)
            let usesOllama = descriptor.id == .ollama || descriptor.id == .hybridAuto

            if usesOllama {
                let models = ollamaVisionModels
                guard models.isEmpty == false else {
                    return [makeCombination(
                        descriptor: descriptor,
                        ollamaModelName: nil,
                        availability: availability,
                        verdict: verdict
                    )]
                }
                return models.map { model in
                    makeCombination(
                        descriptor: descriptor,
                        ollamaModelName: model.name,
                        availability: availability,
                        verdict: verdict
                    )
                }
            }

            return [makeCombination(
                descriptor: descriptor,
                ollamaModelName: nil,
                availability: availability,
                verdict: verdict
            )]
        }
    }

    private static func makeCombination(
        descriptor: LocalProviderDescriptor,
        ollamaModelName: String?,
        availability: LocalProviderAvailability,
        verdict: LocalParserVerdict?
    ) -> SetupGuideCombination {
        SetupGuideCombination(
            providerID: descriptor.id,
            ollamaModelName: ollamaModelName,
            title: title(for: descriptor.id, providerName: descriptor.name, modelName: ollamaModelName),
            pairingSummary: pairingSummary(for: descriptor.id, modelName: ollamaModelName),
            deliveryKind: deliveryKind(for: descriptor.id),
            scores: SetupGuideScoreCatalog.scores(
                for: descriptor.id,
                ollamaModelName: ollamaModelName
            ),
            capabilities: descriptor.parserDefinition?.capabilities ?? [],
            availability: availability,
            badges: verdict?.badges ?? [],
            verdictTier: verdict?.tier ?? .unsupported,
            estimatedPagesPerMinute: verdict?.estimatedPagesPerMinute,
            downloadSizeBytes: descriptor.downloadSizeBytes
        )
    }

    static func deliveryKind(for providerID: LocalProviderID) -> SetupGuideDeliveryKind {
        switch providerID {
        case .appleVision: .system
        case .dotsOCR, .chandraOCR2, .unlimitedOCR: .managedModel
        case .ollama: .ollama
        case .hybridAuto: .hybrid
        }
    }

    private static func title(
        for providerID: LocalProviderID,
        providerName: String,
        modelName: String?
    ) -> String {
        switch providerID {
        case .ollama:
            return modelName.map { "Ollama × \($0)" } ?? "Ollama"
        case .hybridAuto:
            return modelName.map { "Auto × \($0)" } ?? "Auto (Hybrid)"
        case .appleVision, .dotsOCR, .chandraOCR2, .unlimitedOCR:
            return providerName
        }
    }

    private static func pairingSummary(
        for providerID: LocalProviderID,
        modelName: String?
    ) -> String {
        switch providerID {
        case .appleVision:
            return "macOS Vision framework — no model to install"
        case .dotsOCR:
            return "Pinned dots.mocr 4-bit MLX model, managed by okraPDF"
        case .chandraOCR2:
            return "Pinned Chandra OCR 2 oQ8 MLX model, managed by okraPDF"
        case .unlimitedOCR:
            return "Pinned Baidu Unlimited-OCR 4-bit MLX model, managed by okraPDF"
        case .ollama:
            return modelName.map { "Ollama runtime × \($0)" }
                ?? "Ollama runtime × a vision model you install"
        case .hybridAuto:
            return modelName.map { "Native text layer × \($0) for scanned pages" }
                ?? "Native text layer × an Ollama vision model for scanned pages"
        }
    }
}
