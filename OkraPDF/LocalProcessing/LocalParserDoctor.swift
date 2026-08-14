import Darwin
import Foundation

// MARK: - Host probing

/// Coarse memory-bandwidth class for Apple silicon. Decode-side LLM/VLM
/// inference is memory-bandwidth-bound, so this class — not total RAM — is
/// the strongest single predictor of pages-per-minute for local MLX parsers.
enum LocalMemoryBandwidthClass: String, Codable, CaseIterable, Sendable {
    /// M1–M4 base chips, roughly 68–120 GB/s.
    case entry
    /// Pro chips, roughly 150–273 GB/s.
    case pro
    /// Max chips, roughly 300–546 GB/s.
    case max
    /// Ultra chips, roughly 800+ GB/s.
    case ultra

    var typicalGBPerSecond: Int {
        switch self {
        case .entry: 100
        case .pro: 200
        case .max: 400
        case .ultra: 800
        }
    }
}

/// Codable mirror of `ProcessInfo.ThermalState` for diagnostics.
enum LocalThermalState: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    var slowsLongRuns: Bool {
        self == .serious || self == .critical
    }
}

/// Reads Apple-silicon identity from sysctls and maps marketing chip names
/// to bandwidth classes. All reads fail soft — a doctor that cannot identify
/// the chip still works from total memory and the hard requirement gates.
enum LocalChipCatalog {
    static func chipName() -> String? {
        sysctlString("machdep.cpu.brand_string")
    }

    /// `iogpu.wired_limit_mb`: the upper bound macOS places on GPU-wired
    /// (therefore MLX-resident) memory. This, minus headroom, is the honest
    /// model budget — not total unified memory.
    static func gpuWiredLimitBytes() -> Int64? {
        guard let megabytes = sysctlInt64("iogpu.wired_limit_mb"), megabytes > 0 else {
            return nil
        }
        return megabytes * 1_048_576
    }

    /// Parses names like "Apple M2 Pro" / "Apple M1 Ultra" into bandwidth
    /// classes. Intel brand strings ("Intel(R) Core(TM)…") yield nil.
    static func bandwidthClass(forChipName name: String) -> LocalMemoryBandwidthClass? {
        guard name.range(of: #"M\d"#, options: .regularExpression) != nil else {
            return nil
        }
        if name.contains("Ultra") { return .ultra }
        if name.contains("Max") { return .max }
        if name.contains("Pro") { return .pro }
        return .entry
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt64(_ name: String) -> Int64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<Int64>.stride {
            var value: Int64 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return value
        }
        if size == MemoryLayout<Int32>.stride {
            var value: Int32 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return Int64(value)
        }
        return nil
    }
}

// MARK: - Provider fitness catalog

/// Relative output-quality ladder, seeded from
/// `internal/research/ocr-sota-2026-04.md`.
enum LocalParserQualityTier: String, Codable, Sendable, Comparable {
    /// Text-only, no layout structure (Apple Vision).
    case basic
    /// General OCR with layout blocks (Baidu Unlimited-OCR).
    case good
    /// Strong layout/tables/charts (dots.mocr, OmniDocBench 87.5 EN).
    case best
    /// Depends on an externally served model (Ollama and friends).
    case variable

    private var rank: Int {
        switch self {
        case .variable: 0
        case .basic: 1
        case .good: 2
        case .best: 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Everything the doctor knows about one provider beyond its hard
/// `LocalParserResourceRequirements`: how much memory the loaded model
/// occupies, how good its output is, and how fast it runs per bandwidth
/// class. Pages-per-minute figures are conservative seeded estimates pending
/// on-device benchmark calibration (D.6.16 follow-up).
struct LocalParserFitnessProfile: Codable, Equatable, Sendable {
    let providerID: LocalProviderID
    /// Estimated resident footprint: pinned weights × 1.3 (activations, KV,
    /// vision encoder) plus page-image buffers. Zero for system or
    /// externally managed models.
    let estimatedWorkingSetBytes: Int64
    let qualityTier: LocalParserQualityTier
    let pagesPerMinuteByBandwidthClass: [LocalMemoryBandwidthClass: Double]
    let qualityNote: String
    let speedNote: String?

    func estimatedPagesPerMinute(
        for bandwidthClass: LocalMemoryBandwidthClass?
    ) -> Double? {
        pagesPerMinuteByBandwidthClass[bandwidthClass ?? .entry]
    }
}

enum LocalParserFitnessCatalog {
    /// Working-set headroom multiplier applied to pinned weight bytes.
    static let workingSetMultiplier = 1.3
    /// Per-run page-image and activation scratch, in bytes.
    static let pageBufferBytes: Int64 = 600_000_000

    static let appleVision = LocalParserFitnessProfile(
        providerID: .appleVision,
        estimatedWorkingSetBytes: 0,
        qualityTier: .basic,
        pagesPerMinuteByBandwidthClass: [.entry: 40, .pro: 45, .max: 50, .ultra: 55],
        qualityNote: "Fast built-in text recognition; no layout, table, or chart structure.",
        speedNote: "Runs on the Neural Engine; throughput is roughly constant across Macs."
    )

    static let unlimitedOCR = LocalParserFitnessProfile(
        providerID: .unlimitedOCR,
        estimatedWorkingSetBytes: Int64(
            Double(UnlimitedOCRModelManifest.totalBytes) * workingSetMultiplier
        ) + pageBufferBytes,
        qualityTier: .good,
        pagesPerMinuteByBandwidthClass: [.entry: 5, .pro: 9, .max: 15, .ultra: 22],
        qualityNote: "Lightweight general OCR with layout blocks; the smallest managed VLM.",
        speedNote: nil
    )

    static let dotsOCR = LocalParserFitnessProfile(
        providerID: .dotsOCR,
        estimatedWorkingSetBytes: Int64(
            Double(DotsOCRModelManifest.totalBytes) * workingSetMultiplier
        ) + pageBufferBytes,
        qualityTier: .best,
        pagesPerMinuteByBandwidthClass: [.entry: 3, .pro: 6, .max: 11, .ultra: 16],
        qualityNote: "Strongest managed layout, table, and chart quality (OmniDocBench 87.5 EN / 84 ZH in okraPDF research).",
        speedNote: nil
    )

    static let chandraOCR2 = LocalParserFitnessProfile(
        providerID: .chandraOCR2,
        estimatedWorkingSetBytes: Int64(
            Double(ChandraOCRModelManifest.totalBytes) * workingSetMultiplier
        ) + pageBufferBytes,
        qualityTier: .best,
        pagesPerMinuteByBandwidthClass: [.entry: 0.5, .pro: 1, .max: 2, .ultra: 3],
        qualityNote: "Highest managed ParseBench anchor (70.1 overall, 89.2 tables) with labeled layout HTML and source boxes.",
        speedNote: "Minutes per page on entry-bandwidth Macs; reserve it for hard scans, not bulk reading."
    )

    static let ollama = LocalParserFitnessProfile(
        providerID: .ollama,
        estimatedWorkingSetBytes: 0,
        qualityTier: .variable,
        pagesPerMinuteByBandwidthClass: [:],
        qualityNote: "Quality and speed depend on the vision model the local Ollama runtime serves.",
        speedNote: "Ollama owns model memory; this app only streams page images over HTTP."
    )

    static let hybridAuto = LocalParserFitnessProfile(
        providerID: .hybridAuto,
        estimatedWorkingSetBytes: 0,
        qualityTier: .variable,
        pagesPerMinuteByBandwidthClass: [:],
        qualityNote: "Uses embedded PDF text when present and falls back to an Ollama-served VLM for scans.",
        speedNote: "Native-text pages are near-instant; scanned pages run at the Ollama model's speed."
    )

    static func profile(for providerID: LocalProviderID) -> LocalParserFitnessProfile {
        switch providerID {
        case .appleVision: appleVision
        case .dotsOCR: dotsOCR
        case .chandraOCR2: chandraOCR2
        case .hybridAuto: hybridAuto
        case .unlimitedOCR: unlimitedOCR
        case .ollama: ollama
        }
    }
}

// MARK: - Verdicts and diagnosis

enum LocalParserVerdictTier: String, Codable, Sendable {
    /// The single best fit for this Mac.
    case recommended
    /// Fits well within the model memory budget.
    case comfortable
    /// Fits, but close enough to the budget that heavy multitasking may swap.
    case tight
    /// Fails a hard requirement or exceeds the memory budget.
    case unsupported
}

enum LocalParserBadge: String, Codable, Sendable, CaseIterable {
    case recommendedForThisMac = "Recommended for this Mac"
    case fastest = "Fastest"
    case highestQuality = "Highest quality"
}

struct LocalParserVerdict: Codable, Equatable, Sendable {
    let providerID: LocalProviderID
    let providerName: String
    let tier: LocalParserVerdictTier
    let badges: [LocalParserBadge]
    let estimatedPagesPerMinute: Double?
    /// Human-readable, one-line explanations. Always non-empty.
    let reasons: [String]
}

struct LocalParserDiagnosis: Codable, Equatable, Sendable {
    let hostSummary: String
    let modelMemoryBudgetBytes: Int64
    let verdicts: [LocalParserVerdict]
    let recommendedProviderID: LocalProviderID?

    func verdict(for providerID: LocalProviderID) -> LocalParserVerdict? {
        verdicts.first { $0.providerID == providerID }
    }

    /// Privacy-safe plain-text report: host specs and parser verdicts only.
    /// Contains no document names, paths, or user data, so it is safe to
    /// paste into friends-beta feedback.
    func reportText() -> String {
        let budgetText = Self.byteFormatter.string(fromByteCount: modelMemoryBudgetBytes)
        var lines = [
            "Okra local parser diagnosis",
            "Host: \(hostSummary)",
            "Model memory budget: ~\(budgetText)",
        ]
        if let recommendedProviderID,
           let recommended = verdict(for: recommendedProviderID) {
            lines.append("Recommended: \(recommended.providerName)")
        }
        lines.append("")

        for verdict in verdicts {
            let badgeText = verdict.badges.map(\.rawValue).joined(separator: " · ")
            let title = badgeText.isEmpty
                ? verdict.providerName
                : "\(verdict.providerName) — \(badgeText)"
            let marker = verdict.tier == .unsupported ? "✗" : "✓"
            lines.append("\(marker) \(title)")
            if let ppm = verdict.estimatedPagesPerMinute, verdict.tier != .unsupported {
                let ppmText = Self.pagesPerMinuteFormatter.string(from: NSNumber(value: ppm))
                    ?? "\(ppm)"
                lines.append("  Estimated ~\(ppmText) pages/min on this Mac.")
            }
            for reason in verdict.reasons {
                lines.append("  \(reason)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()

    private static let pagesPerMinuteFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

// MARK: - Doctor

/// Deterministic, explainable provider-fit engine. Hard gates come from the
/// existing `LocalParserResourceRequirements`; on top of that the doctor
/// tiers memory headroom against the estimated working set, estimates
/// throughput from the chip's bandwidth class, and picks exactly one
/// recommended provider. Advisory only — it never downloads or installs.
enum LocalParserDoctor {
    struct Subject {
        let providerID: LocalProviderID
        let providerName: String
        let definition: LocalParserDefinition
    }

    static let defaultSubjects: [Subject] = [
        Subject(
            providerID: .dotsOCR,
            providerName: "Dots OCR 1.5",
            definition: LocalParserCatalog.dotsOCR
        ),
        Subject(
            providerID: .chandraOCR2,
            providerName: "Chandra OCR 2",
            definition: LocalParserCatalog.chandraOCR2
        ),
        Subject(
            providerID: .unlimitedOCR,
            providerName: "Baidu Unlimited-OCR",
            definition: LocalParserCatalog.unlimitedOCR
        ),
        Subject(
            providerID: .appleVision,
            providerName: "Apple Vision",
            definition: LocalParserCatalog.appleVision
        ),
        Subject(
            providerID: .hybridAuto,
            providerName: "Auto (Hybrid)",
            definition: LocalParserCatalog.hybridAuto
        ),
        Subject(
            providerID: .ollama,
            providerName: "Ollama",
            definition: LocalParserCatalog.ollama
        ),
    ]

    /// Fraction of total unified memory usable by a model when the GPU wired
    /// limit sysctl is unavailable.
    static let fallbackUsableMemoryFraction = 0.7
    /// Reserved for macOS and the app itself before any model budget math.
    static let systemReserveBytes: Int64 = 2_147_483_648
    /// Working set at or below this fraction of the budget is comfortable.
    static let comfortableHeadroomFraction = 0.6

    static func modelMemoryBudgetBytes(for host: LocalParserHostProfile) -> Int64 {
        let totalBytes = Int64(host.unifiedMemoryGB) * 1_073_741_824
        let usable = host.gpuWiredLimitBytes
            ?? Int64(Double(totalBytes) * fallbackUsableMemoryFraction)
        return max(usable - systemReserveBytes, 0)
    }

    static func evaluate(
        host: LocalParserHostProfile,
        memory: SystemMemoryStatus? = nil,
        subjects: [Subject] = defaultSubjects
    ) -> LocalParserDiagnosis {
        let budget = modelMemoryBudgetBytes(for: host)
        let thermalAdvisory = thermalAdvisoryReason(for: host)
        let memoryPressureAdvisory = memory?.isCriticallyLow == true
            ? "Memory is under pressure right now; quitting heavy apps will help managed models."
            : nil

        var verdicts: [LocalParserVerdict] = subjects.map { subject in
            let fitness = LocalParserFitnessCatalog.profile(for: subject.providerID)
            var reasons: [String] = []

            if case .unsupported(let incompatibilities) = subject.definition.requirements
                .compatibility(with: host) {
                reasons.append(contentsOf: incompatibilities.map {
                    incompatibilityReason($0, providerName: subject.providerName)
                })
                return LocalParserVerdict(
                    providerID: subject.providerID,
                    providerName: subject.providerName,
                    tier: .unsupported,
                    badges: [],
                    estimatedPagesPerMinute: nil,
                    reasons: reasons
                )
            }

            let tier: LocalParserVerdictTier
            if fitness.estimatedWorkingSetBytes > 0, budget > 0 {
                let fraction = Double(fitness.estimatedWorkingSetBytes) / Double(budget)
                if fraction <= comfortableHeadroomFraction {
                    tier = .comfortable
                    reasons.append(
                        "Fits comfortably in this Mac's model memory budget (needs ~\(format(bytes: fitness.estimatedWorkingSetBytes)))."
                    )
                } else if fraction <= 1 {
                    tier = .tight
                    reasons.append(
                        "Fits this Mac's model memory budget with little headroom (needs ~\(format(bytes: fitness.estimatedWorkingSetBytes)) of ~\(format(bytes: budget))); heavy multitasking may cause swap."
                    )
                } else {
                    tier = .unsupported
                    reasons.append(
                        "Needs ~\(format(bytes: fitness.estimatedWorkingSetBytes)) of model memory, over this Mac's ~\(format(bytes: budget)) budget — long runs would swap heavily."
                    )
                }
            } else if fitness.estimatedWorkingSetBytes > 0 {
                tier = .tight
                reasons.append("Could not determine a model memory budget; expect modest throughput.")
            } else {
                tier = .comfortable
                if fitness.estimatedWorkingSetBytes == 0 {
                    reasons.append("No managed model memory footprint.")
                }
            }

            reasons.append(fitness.qualityNote)
            if let speedNote = fitness.speedNote {
                reasons.append(speedNote)
            }
            if let thermalAdvisory, tier != .unsupported {
                reasons.append(thermalAdvisory)
            }
            if let memoryPressureAdvisory,
               tier != .unsupported,
               fitness.estimatedWorkingSetBytes > 0 {
                reasons.append(memoryPressureAdvisory)
            }

            return LocalParserVerdict(
                providerID: subject.providerID,
                providerName: subject.providerName,
                tier: tier,
                badges: [],
                estimatedPagesPerMinute: tier == .unsupported
                    ? nil
                    : fitness.estimatedPagesPerMinute(for: host.memoryBandwidthClass),
                reasons: reasons
            )
        }

        let recommendedID = recommendedProviderID(from: verdicts)
        let fastestID = verdicts
            .filter { $0.tier != .unsupported && $0.estimatedPagesPerMinute != nil }
            .max { ($0.estimatedPagesPerMinute ?? 0) < ($1.estimatedPagesPerMinute ?? 0) }?
            .providerID
        // Ordered-verdict scan keeps quality ties deterministic (first subject
        // wins) now that Dots and Chandra share the .best tier.
        let highestQualityID = verdicts
            .filter { $0.tier != .unsupported }
            .filter {
                LocalParserFitnessCatalog.profile(for: $0.providerID).qualityTier != .variable
            }
            .max { lhs, rhs in
                let lhsTier = LocalParserFitnessCatalog.profile(for: lhs.providerID).qualityTier
                let rhsTier = LocalParserFitnessCatalog.profile(for: rhs.providerID).qualityTier
                return lhsTier < rhsTier
            }?
            .providerID

        verdicts = verdicts.map { verdict in
            var badges: [LocalParserBadge] = []
            if verdict.providerID == recommendedID {
                badges.append(.recommendedForThisMac)
            }
            if verdict.providerID == fastestID {
                badges.append(.fastest)
            }
            if verdict.providerID == highestQualityID {
                badges.append(.highestQuality)
            }
            return LocalParserVerdict(
                providerID: verdict.providerID,
                providerName: verdict.providerName,
                tier: verdict.providerID == recommendedID ? .recommended : verdict.tier,
                badges: badges,
                estimatedPagesPerMinute: verdict.estimatedPagesPerMinute,
                reasons: verdict.reasons
            )
        }

        return LocalParserDiagnosis(
            hostSummary: hostSummary(for: host),
            modelMemoryBudgetBytes: budget,
            verdicts: verdicts,
            recommendedProviderID: recommendedID
        )
    }

    /// Best quality among comfortable providers first; tight providers only
    /// when nothing fits comfortably. Externally managed (variable-quality)
    /// providers are never the headline recommendation while a managed or
    /// system parser is usable.
    private static func recommendedProviderID(
        from verdicts: [LocalParserVerdict]
    ) -> LocalProviderID? {
        let ranked = verdicts
            .filter { $0.tier == .comfortable || $0.tier == .tight }
            .sorted { lhs, rhs in
                score(for: lhs) > score(for: rhs)
            }
        return ranked.first?.providerID
    }

    private static func score(for verdict: LocalParserVerdict) -> Double {
        let fitness = LocalParserFitnessCatalog.profile(for: verdict.providerID)
        let tierScore = verdict.tier == .comfortable ? 1_000.0 : 0.0
        let qualityScore: Double
        switch fitness.qualityTier {
        case .best: qualityScore = 300
        case .good: qualityScore = 200
        case .basic: qualityScore = 100
        case .variable: qualityScore = 50
        }
        return tierScore + qualityScore + (verdict.estimatedPagesPerMinute ?? 0)
    }

    private static func thermalAdvisoryReason(
        for host: LocalParserHostProfile
    ) -> String? {
        if host.isLowPowerModeEnabled {
            return "Low Power Mode is on; long local runs will be slower."
        }
        guard let thermalState = host.thermalState, thermalState.slowsLongRuns else {
            return nil
        }
        return "This Mac is thermally constrained (\(thermalState.rawValue)); long local runs will be slower."
    }

    static func hostSummary(for host: LocalParserHostProfile) -> String {
        var parts: [String] = []
        parts.append(host.chipName ?? (host.architecture == .intel ? "Intel Mac" : "Apple silicon"))
        parts.append("\(host.unifiedMemoryGB) GB unified memory")
        parts.append("macOS \(host.macOSMajorVersion)")
        if let availableDiskBytes = host.availableDiskBytes {
            parts.append("\(format(bytes: availableDiskBytes)) free disk")
        }
        if let thermalState = host.thermalState, thermalState != .nominal {
            parts.append("thermal: \(thermalState.rawValue)")
        }
        if host.isLowPowerModeEnabled {
            parts.append("Low Power Mode")
        }
        return parts.joined(separator: " · ")
    }

    private static func incompatibilityReason(
        _ incompatibility: LocalParserIncompatibility,
        providerName: String
    ) -> String {
        switch incompatibility {
        case .architecture(let architecture) where architecture == .intel:
            return "\(providerName) requires Apple silicon."
        case .architecture(let architecture):
            return "\(providerName) does not support \(architecture.rawValue) Macs."
        case .macOS(let minimumMajorVersion):
            return "\(providerName) requires macOS \(minimumMajorVersion) or later."
        case .unifiedMemory(let minimumGB):
            return "\(providerName) requires at least \(minimumGB) GB unified memory."
        case .freeDisk(let requiredBytes, let availableBytes):
            return "\(providerName) setup needs \(format(bytes: requiredBytes)) free disk; \(format(bytes: availableBytes)) available."
        }
    }

    private static func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}
