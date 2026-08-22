import Foundation
import Testing
@testable import Okra

struct OllamaParserDefinitionTests {
    @Test(
        "Ollama is a runtime-selected API VLM with the Markdown adapter",
        .bug("https://github.com/okrapdf/desktop/issues/99")
    )
    func runtimeAndAdapter() throws {
        #expect(LocalParserCatalog.ollama.runtime == .apiVLM)
        #expect(LocalParserCatalog.ollama.outputAdapter == .markdownV1)
        let endpoint = try #require(LocalParserCatalog.ollama.modelDelivery.apiVlmEndpoint)
        #expect(endpoint.baseURL == "http://127.0.0.1:11434")
        #expect(endpoint.model == nil)
        #expect(endpoint.runtimeType == .ollama)
        #expect(endpoint.responseFormat == "markdown")
    }

    @Test("Ollama ships and downloads no pinned weights")
    func noManagedWeights() {
        let descriptor = OllamaProcessingProvider().descriptor
        #expect(LocalParserCatalog.ollama.modelDelivery.pinnedPackage == nil)
        #expect(descriptor.downloadSizeBytes == nil)
        #expect(descriptor.installLocation == nil)
    }

    @Test("Runtime-selected requirements make no model-specific hardware assumption")
    func genericCompatibility() {
        let host = LocalParserHostProfile(
            architecture: .intel,
            macOSMajorVersion: 13,
            unifiedMemoryGB: 4,
            availableDiskBytes: nil
        )
        #expect(LocalParserCatalog.ollama.requirements.compatibility(with: host) == .supported)
    }

    @Test("API-VLM delivery round-trips for run provenance")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(LocalParserCatalog.ollama)
        let decoded = try JSONDecoder().decode(LocalParserDefinition.self, from: data)
        #expect(decoded == LocalParserCatalog.ollama)
    }

    @Test("Legacy Chandra provider preference migrates to Ollama")
    func legacyProviderMigration() {
        #expect(LocalProviderID.persisted(rawValue: "chandra") == .ollama)
        #expect(LocalProviderID.persisted(rawValue: "ollama") == .ollama)
    }
}
