import Foundation
import Testing
@testable import Okra

struct LocalParserDoctorTests {
    // MARK: Chip catalog

    @Test("Chip names map to memory bandwidth classes")
    func chipBandwidthClasses() {
        #expect(LocalChipCatalog.bandwidthClass(forChipName: "Apple M1") == .entry)
        #expect(LocalChipCatalog.bandwidthClass(forChipName: "Apple M4") == .entry)
        #expect(LocalChipCatalog.bandwidthClass(forChipName: "Apple M2 Pro") == .pro)
        #expect(LocalChipCatalog.bandwidthClass(forChipName: "Apple M4 Pro") == .pro)
        #expect(LocalChipCatalog.bandwidthClass(forChipName: "Apple M3 Max") == .max)
        #expect(LocalChipCatalog.bandwidthClass(forChipName: "Apple M1 Ultra") == .ultra)
        #expect(LocalChipCatalog.bandwidthClass(forChipName: "Apple M2 Ultra") == .ultra)
        #expect(
            LocalChipCatalog.bandwidthClass(
                forChipName: "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz"
            ) == nil
        )
    }

    // MARK: Memory budget

    @Test("Memory budget prefers the GPU wired limit over total RAM")
    func memoryBudgetUsesWiredLimit() {
        let host = makeHost(
            unifiedMemoryGB: 16,
            gpuWiredLimitBytes: 12_884_901_888 // 12 GB
        )

        #expect(
            LocalParserDoctor.modelMemoryBudgetBytes(for: host)
                == 12_884_901_888 - LocalParserDoctor.systemReserveBytes
        )
    }

    @Test("Memory budget falls back to a fraction of total RAM")
    func memoryBudgetFallback() {
        let host = makeHost(unifiedMemoryGB: 16)
        let totalBytes = Int64(16) * 1_073_741_824
        let expected = Int64(Double(totalBytes) * LocalParserDoctor.fallbackUsableMemoryFraction)
            - LocalParserDoctor.systemReserveBytes

        #expect(LocalParserDoctor.modelMemoryBudgetBytes(for: host) == expected)
    }

    // MARK: Recommendation scenarios

    @Test("Baseline 16 GB Apple-silicon Mac recommends Dots OCR")
    func baselineAppleSiliconRecommendsDots() {
        let host = makeHost(chipName: "Apple M1", unifiedMemoryGB: 16)

        let diagnosis = LocalParserDoctor.evaluate(host: host)

        #expect(diagnosis.recommendedProviderID == .dotsOCR)
        let dots = diagnosis.verdict(for: .dotsOCR)
        #expect(dots?.tier == .recommended)
        #expect(dots?.badges.contains(.recommendedForThisMac) == true)
        #expect(dots?.badges.contains(.highestQuality) == true)
        #expect(dots?.estimatedPagesPerMinute == 3)

        let unlimited = diagnosis.verdict(for: .unlimitedOCR)
        #expect(unlimited?.tier == .comfortable)

        // Apple Vision out-paces every VLM and earns the speed badge.
        let appleVision = diagnosis.verdict(for: .appleVision)
        #expect(appleVision?.badges.contains(.fastest) == true)
    }

    @Test("8 GB Apple-silicon Mac falls back to Apple Vision")
    func lowMemoryMacRecommendsAppleVision() {
        let host = makeHost(chipName: "Apple M1", unifiedMemoryGB: 8)

        let diagnosis = LocalParserDoctor.evaluate(host: host)

        #expect(diagnosis.recommendedProviderID == .appleVision)
        #expect(diagnosis.verdict(for: .dotsOCR)?.tier == .unsupported)
        #expect(diagnosis.verdict(for: .unlimitedOCR)?.tier == .unsupported)
        #expect(
            diagnosis.verdict(for: .dotsOCR)?.reasons.contains(
                "Dots OCR 1.5 requires at least 16 GB unified memory."
            ) == true
        )
    }

    @Test("Intel Mac never recommends an externally managed runtime")
    func intelMacRecommendsAppleVision() {
        let host = makeHost(
            architecture: .intel,
            chipName: nil,
            unifiedMemoryGB: 16
        )

        let diagnosis = LocalParserDoctor.evaluate(host: host)

        #expect(diagnosis.recommendedProviderID == .appleVision)
        #expect(diagnosis.verdict(for: .dotsOCR)?.tier == .unsupported)
        #expect(diagnosis.verdict(for: .dotsOCR)?.reasons.first == "Dots OCR 1.5 requires Apple silicon.")
        // Ollama remains usable but is never the headline recommendation.
        #expect(diagnosis.verdict(for: .ollama)?.tier == .comfortable)
        #expect(diagnosis.verdict(for: .ollama)?.badges.isEmpty == true)
    }

    @Test("Tight GPU wired limit downgrades Dots below Unlimited-OCR")
    func tightBudgetPrefersLighterModel() {
        // Budget = wired limit − reserve ≈ 7 GB: Dots (~5.2 GB) is tight,
        // Unlimited-OCR (~3.8 GB) stays comfortable.
        let host = makeHost(
            chipName: "Apple M2 Pro",
            unifiedMemoryGB: 16,
            gpuWiredLimitBytes: 7_000_000_000 + LocalParserDoctor.systemReserveBytes
        )

        let diagnosis = LocalParserDoctor.evaluate(host: host)

        #expect(diagnosis.recommendedProviderID == .unlimitedOCR)
        #expect(diagnosis.verdict(for: .dotsOCR)?.tier == .tight)
        #expect(
            diagnosis.verdict(for: .dotsOCR)?.reasons.contains(
                where: { $0.contains("little headroom") }
            ) == true
        )
        // The speed estimate follows the Pro bandwidth class.
        #expect(diagnosis.verdict(for: .unlimitedOCR)?.estimatedPagesPerMinute == 9)
    }

    @Test("Model working sets over the memory budget are unsupported")
    func overBudgetModelsAreUnsupported() {
        // Budget ≈ 2 GB: both managed VLMs exceed it.
        let host = makeHost(
            chipName: "Apple M1",
            unifiedMemoryGB: 16,
            gpuWiredLimitBytes: 2_000_000_000 + LocalParserDoctor.systemReserveBytes
        )

        let diagnosis = LocalParserDoctor.evaluate(host: host)

        #expect(diagnosis.recommendedProviderID == .appleVision)
        #expect(diagnosis.verdict(for: .dotsOCR)?.tier == .unsupported)
        #expect(
            diagnosis.verdict(for: .unlimitedOCR)?.reasons.contains(
                where: { $0.contains("swap heavily") }
            ) == true
        )
    }

    @Test("Low free disk gates managed model setup")
    func lowDiskGatesDownloads() {
        let host = makeHost(
            chipName: "Apple M1",
            unifiedMemoryGB: 16,
            availableDiskBytes: 4_000_000_000 // enough for Unlimited, not Dots
        )

        let diagnosis = LocalParserDoctor.evaluate(host: host)

        #expect(diagnosis.verdict(for: .dotsOCR)?.tier == .unsupported)
        #expect(
            diagnosis.verdict(for: .dotsOCR)?.reasons.contains(
                where: { $0.contains("free disk") }
            ) == true
        )
        #expect(diagnosis.recommendedProviderID == .unlimitedOCR)
    }

    @Test("Thermal pressure and Low Power Mode add advisories")
    func thermalAdvisories() {
        let lowPowerHost = makeHost(
            chipName: "Apple M1",
            unifiedMemoryGB: 16,
            isLowPowerModeEnabled: true
        )
        let lowPowerDiagnosis = LocalParserDoctor.evaluate(host: lowPowerHost)
        #expect(
            lowPowerDiagnosis.verdict(for: .dotsOCR)?.reasons.contains(
                where: { $0.contains("Low Power Mode") }
            ) == true
        )
        #expect(lowPowerDiagnosis.hostSummary.contains("Low Power Mode"))

        let hotHost = makeHost(
            chipName: "Apple M1",
            unifiedMemoryGB: 16,
            thermalState: .serious
        )
        let hotDiagnosis = LocalParserDoctor.evaluate(host: hotHost)
        #expect(
            hotDiagnosis.verdict(for: .dotsOCR)?.reasons.contains(
                where: { $0.contains("thermally constrained") }
            ) == true
        )
    }

    @Test("Current memory pressure warns on managed models")
    func memoryPressureAdvisory() {
        let host = makeHost(chipName: "Apple M1", unifiedMemoryGB: 16)
        let pressuredMemory = SystemMemoryStatus(
            freeBytes: 512 * 1_048_576,
            swapUsedBytes: 6 * 1_073_741_824,
            swapTotalBytes: 8 * 1_073_741_824
        )

        let diagnosis = LocalParserDoctor.evaluate(host: host, memory: pressuredMemory)

        #expect(
            diagnosis.verdict(for: .dotsOCR)?.reasons.contains(
                where: { $0.contains("under pressure right now") }
            ) == true
        )
        // System and externally managed providers carry no working-set warning.
        #expect(
            diagnosis.verdict(for: .appleVision)?.reasons.contains(
                where: { $0.contains("under pressure right now") }
            ) != true
        )
    }

    // MARK: Report

    @Test("Report summarizes the host, recommendation, and every provider")
    func reportText() {
        let host = makeHost(
            chipName: "Apple M2 Pro",
            unifiedMemoryGB: 16,
            availableDiskBytes: 96_000_000_000
        )

        let report = LocalParserDoctor.evaluate(host: host).reportText()

        #expect(report.contains("Okra local parser diagnosis"))
        #expect(report.contains("Apple M2 Pro · 16 GB unified memory · macOS 14"))
        #expect(report.contains("Recommended: Dots OCR 1.5"))
        #expect(report.contains("Dots OCR 1.5"))
        #expect(report.contains("Baidu Unlimited-OCR"))
        #expect(report.contains("Apple Vision"))
        #expect(report.contains("Recommended for this Mac"))
    }

    @Test("Diagnosis round-trips for support bundles")
    func codableRoundTrip() throws {
        let host = makeHost(chipName: "Apple M1", unifiedMemoryGB: 16)
        let diagnosis = LocalParserDoctor.evaluate(host: host)

        let data = try JSONEncoder().encode(diagnosis)
        let decoded = try JSONDecoder().decode(LocalParserDiagnosis.self, from: data)

        #expect(decoded == diagnosis)
    }

    // MARK: Host profile probe additions

    @Test("Host profile preserves extended fields when ignoring disk")
    func ignoringAvailableDiskKeepsExtendedFields() {
        let host = makeHost(
            chipName: "Apple M4 Pro",
            unifiedMemoryGB: 24,
            availableDiskBytes: 50_000_000_000,
            gpuWiredLimitBytes: 16_000_000_000,
            thermalState: .fair,
            isLowPowerModeEnabled: true
        )

        let ignoring = host.ignoringAvailableDisk()

        #expect(ignoring.availableDiskBytes == nil)
        #expect(ignoring.chipName == "Apple M4 Pro")
        #expect(ignoring.memoryBandwidthClass == .pro)
        #expect(ignoring.gpuWiredLimitBytes == 16_000_000_000)
        #expect(ignoring.thermalState == .fair)
        #expect(ignoring.isLowPowerModeEnabled)
    }

    // MARK: Helpers

    private func makeHost(
        architecture: LocalParserArchitecture = .appleSilicon,
        macOSMajorVersion: Int = 14,
        chipName: String? = "Apple M1",
        unifiedMemoryGB: Int,
        availableDiskBytes: Int64? = 100_000_000_000,
        gpuWiredLimitBytes: Int64? = nil,
        thermalState: LocalThermalState? = nil,
        isLowPowerModeEnabled: Bool = false
    ) -> LocalParserHostProfile {
        LocalParserHostProfile(
            architecture: architecture,
            macOSMajorVersion: macOSMajorVersion,
            unifiedMemoryGB: unifiedMemoryGB,
            availableDiskBytes: availableDiskBytes,
            chipName: chipName,
            memoryBandwidthClass: chipName.flatMap(
                LocalChipCatalog.bandwidthClass(forChipName:)
            ),
            gpuWiredLimitBytes: gpuWiredLimitBytes,
            thermalState: thermalState,
            isLowPowerModeEnabled: isLowPowerModeEnabled
        )
    }
}
