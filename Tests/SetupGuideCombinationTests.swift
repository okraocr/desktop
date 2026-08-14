import Foundation
import Testing
@testable import Okra

struct SetupGuideCombinationTests {
    private let hostProfile = LocalParserHostProfile(
        architecture: .appleSilicon,
        macOSMajorVersion: 14,
        unifiedMemoryGB: 32,
        availableDiskBytes: 100_000_000_000,
        chipName: "Apple M2 Pro",
        memoryBandwidthClass: .pro
    )

    private var descriptors: [LocalProviderDescriptor] {
        [
            LocalProviderDescriptor(
                id: .appleVision,
                name: "Apple Vision",
                summary: "",
                setupNote: nil,
                parserDefinition: LocalParserCatalog.appleVision
            ),
            LocalProviderDescriptor(
                id: .dotsOCR,
                name: "Dots OCR 1.5",
                summary: "",
                setupNote: nil,
                parserDefinition: LocalParserCatalog.dotsOCR
            ),
            LocalProviderDescriptor(
                id: .unlimitedOCR,
                name: "Baidu Unlimited-OCR",
                summary: "",
                setupNote: nil,
                parserDefinition: LocalParserCatalog.unlimitedOCR
            ),
            LocalProviderDescriptor(
                id: .hybridAuto,
                name: "Auto (Hybrid)",
                summary: "",
                setupNote: nil,
                parserDefinition: LocalParserCatalog.hybridAuto
            ),
            LocalProviderDescriptor(
                id: .ollama,
                name: "Ollama",
                summary: "",
                setupNote: nil,
                parserDefinition: LocalParserCatalog.ollama
            ),
        ]
    }

    private var diagnosis: LocalParserDiagnosis {
        LocalParserDoctor.evaluate(
            host: hostProfile,
            subjects: descriptors.map {
                LocalParserDoctor.Subject(
                    providerID: $0.id,
                    providerName: $0.name,
                    definition: $0.parserDefinition ?? LocalParserCatalog.appleVision
                )
            }
        )
    }

    private func visionModel(_ name: String) -> OllamaModel {
        OllamaModel(
            name: name,
            size: 5_000_000_000,
            digest: "sha256:test",
            family: nil,
            parameterSize: nil,
            quantizationLevel: nil,
            capabilities: ["vision"]
        )
    }

    private func combinations(
        availability: [LocalProviderID: LocalProviderAvailability] = [:],
        visionModels: [OllamaModel] = []
    ) -> [SetupGuideCombination] {
        SetupGuideCombinationCatalog.combinations(
            descriptors: descriptors,
            availabilityByProvider: availability,
            diagnosis: diagnosis,
            ollamaVisionModels: visionModels
        )
    }

    @Test("Every combination scores all five ParseBench dimensions within 0…1")
    func scoresCoverEveryDimension() {
        let combos = combinations(visionModels: [visionModel("qwen3-vl:8b")])
        #expect(combos.isEmpty == false)
        for combo in combos {
            #expect(combo.scores.count == ParseBenchDimension.allCases.count)
            for dimension in ParseBenchDimension.allCases {
                let score = combo.score(for: dimension)
                #expect(score >= 0 && score <= 1)
            }
        }
    }

    @Test("Ollama-backed providers expand to one pairing per installed vision model")
    func ollamaPairingsExpandPerVisionModel() {
        let models = [visionModel("qwen3-vl:8b"), visionModel("llava:7b")]
        let combos = combinations(visionModels: models)

        let ollamaCombos = combos.filter { $0.providerID == .ollama }
        let hybridCombos = combos.filter { $0.providerID == .hybridAuto }
        #expect(ollamaCombos.count == 2)
        #expect(hybridCombos.count == 2)
        #expect(Set(ollamaCombos.map(\.ollamaModelName)) == Set(models.map(\.name)))
        #expect(ollamaCombos.map(\.id).contains("ollama:qwen3-vl:8b"))
        #expect(ollamaCombos.first { $0.ollamaModelName == "qwen3-vl:8b" }?.title == "Ollama × qwen3-vl:8b")
    }

    @Test("Without vision models, Ollama pairings collapse to a single unpaired entry")
    func ollamaPairingsCollapseWithoutModels() {
        let combos = combinations()
        #expect(combos.filter { $0.providerID == .ollama }.count == 1)
        #expect(combos.filter { $0.providerID == .hybridAuto }.count == 1)
        #expect(combos.first { $0.providerID == .ollama }?.ollamaModelName == nil)
    }

    @Test("Hybrid pairing keeps the native-text faithfulness floor")
    func hybridKeepsNativeTextFaithfulnessFloor() {
        let combos = combinations(visionModels: [visionModel("llava:7b")])
        let hybrid = combos.first { $0.providerID == .hybridAuto }
        let ollama = combos.first { $0.providerID == .ollama }
        #expect(hybrid?.score(for: .contentFaithfulness) == 0.88)
        #expect((hybrid?.score(for: .contentFaithfulness) ?? 0) > (ollama?.score(for: .contentFaithfulness) ?? 0))
    }

    @Test("Larger served models score higher on structure")
    func largerOllamaModelsScoreHigher() {
        let combos = combinations(visionModels: [visionModel("qwen3-vl:32b"), visionModel("llava:7b")])
        let big = combos.first { $0.ollamaModelName == "qwen3-vl:32b" && $0.providerID == .ollama }
        let small = combos.first { $0.ollamaModelName == "llava:7b" && $0.providerID == .ollama }
        #expect((big?.score(for: .tables) ?? 0) > (small?.score(for: .tables) ?? 0))
    }

    @Test("On-device-only filter keeps system and managed models, drops Ollama pairings")
    func onDeviceOnlyFilter() {
        var filter = SetupGuideCombinationFilter()
        filter.onDeviceOnly = true
        let filtered = combinations(visionModels: [visionModel("qwen3-vl:8b")]).filter(filter.matches)
        #expect(filtered.isEmpty == false)
        #expect(filtered.allSatisfy { $0.deliveryKind == .system || $0.deliveryKind == .managedModel })
    }

    @Test("Zero-setup filter drops pairings that need downloads")
    func zeroSetupFilter() {
        var filter = SetupGuideCombinationFilter()
        filter.zeroSetupOnly = true
        let availability: [LocalProviderID: LocalProviderAvailability] = [
            .appleVision: .ready,
            .dotsOCR: .setupRequired("Setup required"),
        ]
        let filtered = combinations(availability: availability).filter(filter.matches)
        #expect(filtered.contains { $0.providerID == .appleVision })
        #expect(filtered.contains { $0.providerID == .dotsOCR } == false)
    }

    @Test("Recommended filter keeps only the doctor's pick for this Mac")
    func recommendedOnlyFilter() {
        var filter = SetupGuideCombinationFilter()
        filter.recommendedOnly = true
        let filtered = combinations().filter(filter.matches)
        #expect(filtered.isEmpty == false)
        #expect(filtered.allSatisfy { $0.isRecommended })
        #expect(filtered.contains { $0.providerID == diagnosis.recommendedProviderID })
    }

    @Test("Capability filter requires every requested capability")
    func capabilityFilter() {
        var filter = SetupGuideCombinationFilter()
        filter.requiredCapabilities = [.tables]
        let filtered = combinations().filter(filter.matches)
        #expect(filtered.contains { $0.providerID == .appleVision } == false)
        #expect(filtered.contains { $0.providerID == .dotsOCR })
    }

    @Test("Delivery-kind filter narrows to the selected kinds")
    func deliveryKindFilter() {
        var filter = SetupGuideCombinationFilter()
        filter.deliveryKinds = [.managedModel]
        let filtered = combinations(visionModels: [visionModel("qwen3-vl:8b")]).filter(filter.matches)
        #expect(filtered.count == 2)
        #expect(Set(filtered.map(\.providerID)) == [.dotsOCR, .unlimitedOCR])
    }

    @Test("Combined filters intersect")
    func combinedFiltersIntersect() {
        var filter = SetupGuideCombinationFilter()
        filter.onDeviceOnly = true
        filter.requiredCapabilities = [.charts]
        let filtered = combinations(visionModels: [visionModel("qwen3-vl:8b")]).filter(filter.matches)
        #expect(filtered.isEmpty == false)
        #expect(filtered.allSatisfy {
            ($0.deliveryKind == .system || $0.deliveryKind == .managedModel)
                && $0.capabilities.contains(.charts)
        })
    }

    @Test("Default filter matches everything and reports inactive")
    func defaultFilterMatchesEverything() {
        let filter = SetupGuideCombinationFilter()
        #expect(filter.isActive == false)
        let all = combinations(visionModels: [visionModel("qwen3-vl:8b")])
        #expect(all.filter(filter.matches).count == all.count)
    }
}
