import Foundation
import Testing
@testable import Okra

struct LocalParserDefinitionTests {
    @Test("Current providers declare distinct runtimes and output adapters")
    func providerContracts() {
        #expect(LocalParserCatalog.appleVision.runtime == .appleVision)
        #expect(LocalParserCatalog.appleVision.outputAdapter == .plainTextV1)
        #expect(LocalParserCatalog.hybridAuto.runtime == .hybrid)
        #expect(LocalParserCatalog.hybridAuto.outputAdapter == .hybridMarkdownV1)
        #expect(LocalParserCatalog.dotsOCR.runtime == .mlxVLM)
        #expect(LocalParserCatalog.dotsOCR.outputAdapter == .dotsLayoutJSONV1)
        #expect(LocalParserCatalog.unlimitedOCR.runtime == .mlxVLM)
        #expect(LocalParserCatalog.unlimitedOCR.outputAdapter == .unlimitedOCRTokensV1)
        #expect(LocalParserCatalog.chandraOCR2.runtime == .mlxVLM)
        #expect(LocalParserCatalog.chandraOCR2.outputAdapter == .chandraHTMLV1)
    }

    @Test("Chandra OCR 2 keeps pinned model lineage, terms, and artifacts")
    func chandraOCRLineage() throws {
        let package = try #require(LocalParserCatalog.chandraOCR2.modelDelivery.pinnedPackage)

        #expect(package.upstreamRepository == "datalab-to/chandra-ocr-2")
        #expect(package.repository == "mlx-community/chandra-ocr-2-oQ8")
        #expect(package.revision == "eafcb4c79468ff6cf8b76ecc3aedbffe0dd82282")
        #expect(package.format == .mlxSafetensors)
        #expect(package.quantization == LocalModelQuantization(bits: 8, scheme: "affine-int8-group-64"))
        #expect(package.licenseSPDXIdentifier == "LicenseRef-OpenRAIL")
        #expect(package.licenseURL?.absoluteString.contains("datalab-to/chandra-ocr-2") == true)
        #expect(package.licenseRevision == "af93b47dba1b47b6640c86ccf487ed2260ab9a09")
        #expect(package.licenseNotice?.contains("OpenRAIL") == true)
        #expect(package.artifacts == ChandraOCRModelManifest.artifacts)
        #expect(package.totalBytes == 5_156_826_785)
    }

    @Test("Chandra OCR 2 artifacts retain revision-scoped download URLs")
    func chandraOCRArtifactDownloadURL() throws {
        let package = try #require(LocalParserCatalog.chandraOCR2.modelDelivery.pinnedPackage)
        let artifact = try #require(package.artifacts.first { $0.path == "model-00001-of-00002.safetensors" })
        let url = try #require(package.downloadURL(for: artifact))

        #expect(
            url.absoluteString
                == "https://huggingface.co/mlx-community/chandra-ocr-2-oQ8/resolve/eafcb4c79468ff6cf8b76ecc3aedbffe0dd82282/model-00001-of-00002.safetensors?download=true"
        )
    }

    @Test("Chandra OCR 2 supports a macOS 14, 16 GB Apple-silicon Mac with setup space")
    func chandraOCRBaselineMacCompatibility() {
        let host = LocalParserHostProfile(
            architecture: .appleSilicon,
            macOSMajorVersion: 14,
            unifiedMemoryGB: 16,
            availableDiskBytes: 8_000_000_000
        )

        #expect(LocalParserCatalog.chandraOCR2.requirements.compatibility(with: host) == .supported)
    }

    @Test("Chandra OCR 2 reports every incompatible host constraint")
    func chandraOCRIncompatibleHost() {
        let host = LocalParserHostProfile(
            architecture: .intel,
            macOSMajorVersion: 13,
            unifiedMemoryGB: 8,
            availableDiskBytes: 1_000_000_000
        )

        #expect(
            LocalParserCatalog.chandraOCR2.requirements.compatibility(with: host)
                == .unsupported([
                    .architecture(.intel),
                    .macOS(minimumMajorVersion: 14),
                    .unifiedMemory(minimumGB: 16),
                    .freeDisk(requiredBytes: 8_000_000_000, availableBytes: 1_000_000_000),
                ])
        )
    }

    @Test("Dots OCR keeps pinned model lineage, terms, and artifacts")
    func dotsOCRLineage() throws {
        let package = try #require(LocalParserCatalog.dotsOCR.modelDelivery.pinnedPackage)

        #expect(package.upstreamRepository == "dots-studio/dots.mocr")
        #expect(package.repository == "mlx-community/dots.mocr-4bit")
        #expect(package.revision == "708b576de556b0cdba615ecd211db3b951ec09ef")
        #expect(package.format == .mlxSafetensors)
        #expect(package.quantization == LocalModelQuantization(bits: 4, scheme: "affine-int4-group-64"))
        #expect(package.parameterCount == 3_000_000_000)
        #expect(package.licenseSPDXIdentifier == "LicenseRef-dots-mocr")
        #expect(package.licenseURL?.absoluteString.contains("dots.mocr%20LICENSE%20AGREEMENT") == true)
        #expect(package.licenseRevision == "e539fbb52280393adc081b289ec597430a0f9031")
        #expect(package.licenseNotice?.contains("acceptable-use") == true)
        #expect(package.artifacts == DotsOCRModelManifest.artifacts)
        #expect(package.totalBytes == 3_538_447_417)
    }

    @Test("Dots OCR artifacts retain revision-scoped download URLs")
    func dotsOCRArtifactDownloadURL() throws {
        let package = try #require(LocalParserCatalog.dotsOCR.modelDelivery.pinnedPackage)
        let artifact = try #require(package.artifacts.first { $0.path == "model.safetensors" })
        let url = try #require(package.downloadURL(for: artifact))

        #expect(
            url.absoluteString
                == "https://huggingface.co/mlx-community/dots.mocr-4bit/resolve/708b576de556b0cdba615ecd211db3b951ec09ef/model.safetensors?download=true"
        )
    }

    @Test("Dots OCR supports a macOS 14, 16 GB Apple-silicon Mac with setup space")
    func dotsOCRBaselineMacCompatibility() {
        let host = LocalParserHostProfile(
            architecture: .appleSilicon,
            macOSMajorVersion: 14,
            unifiedMemoryGB: 16,
            availableDiskBytes: 5_000_000_000
        )

        #expect(LocalParserCatalog.dotsOCR.requirements.compatibility(with: host) == .supported)
    }

    @Test("Dots OCR reports its macOS 14 runtime floor")
    func dotsOCRRejectsMacOS13Runtime() {
        let host = LocalParserHostProfile(
            architecture: .appleSilicon,
            macOSMajorVersion: 13,
            unifiedMemoryGB: 16,
            availableDiskBytes: 5_000_000_000
        )

        #expect(
            LocalParserCatalog.dotsOCR.requirements.compatibility(with: host)
                == .unsupported([.macOS(minimumMajorVersion: 14)])
        )
    }

    @Test("Unlimited OCR keeps pinned model lineage and artifacts")
    func unlimitedOCRLineage() throws {
        let package = try #require(LocalParserCatalog.unlimitedOCR.modelDelivery.pinnedPackage)

        #expect(package.upstreamRepository == "baidu/Unlimited-OCR")
        #expect(package.repository == "sahilchachra/unlimited-ocr-4bit-mlx")
        #expect(package.revision == "5df80100fca719eca44a4f5ec2e5a63d31881eb6")
        #expect(package.format == .mlxSafetensors)
        #expect(package.quantization == LocalModelQuantization(bits: 4, scheme: "affine-int4-group-64"))
        #expect(package.licenseSPDXIdentifier == "MIT")
        #expect(package.artifacts == UnlimitedOCRModelManifest.artifacts)
        #expect(package.totalBytes == 2_461_271_624)
    }

    @Test("Pinned model artifacts retain revision-scoped download URLs")
    func artifactDownloadURL() throws {
        let package = try #require(LocalParserCatalog.unlimitedOCR.modelDelivery.pinnedPackage)
        let artifact = try #require(package.artifacts.first { $0.path == "model.safetensors" })
        let url = try #require(package.downloadURL(for: artifact))

        #expect(
            url.absoluteString
                == "https://huggingface.co/sahilchachra/unlimited-ocr-4bit-mlx/resolve/5df80100fca719eca44a4f5ec2e5a63d31881eb6/model.safetensors?download=true"
        )
    }

    @Test("Unlimited OCR supports the baseline 16 GB Apple-silicon Mac")
    func baselineMacCompatibility() {
        let host = LocalParserHostProfile(
            architecture: .appleSilicon,
            macOSMajorVersion: 13,
            unifiedMemoryGB: 16,
            availableDiskBytes: 3_000_000_000
        )

        #expect(LocalParserCatalog.unlimitedOCR.requirements.compatibility(with: host) == .supported)
    }

    @Test("Unlimited OCR reports every incompatible host constraint")
    func incompatibleHost() {
        let host = LocalParserHostProfile(
            architecture: .intel,
            macOSMajorVersion: 12,
            unifiedMemoryGB: 8,
            availableDiskBytes: 1_000_000_000
        )

        #expect(
            LocalParserCatalog.unlimitedOCR.requirements.compatibility(with: host)
                == .unsupported([
                    .architecture(.intel),
                    .macOS(minimumMajorVersion: 13),
                    .unifiedMemory(minimumGB: 16),
                    .freeDisk(requiredBytes: 3_000_000_000, availableBytes: 1_000_000_000),
                ])
        )
    }

    @Test("Parser definitions round-trip for run provenance")
    func codableRoundTrip() throws {
        let definitions = [
            LocalParserCatalog.appleVision,
            LocalParserCatalog.hybridAuto,
            LocalParserCatalog.dotsOCR,
            LocalParserCatalog.unlimitedOCR,
            LocalParserCatalog.chandraOCR2,
        ]
        let data = try JSONEncoder().encode(definitions)
        let decoded = try JSONDecoder().decode([LocalParserDefinition].self, from: data)

        #expect(decoded == definitions)
    }

    @Test("Provider setup size comes from its pinned package")
    func providerDownloadSize() {
        let descriptor = DotsOCRProcessingProvider().descriptor

        #expect(descriptor.downloadSizeBytes == DotsOCRModelManifest.totalBytes)
    }
}
