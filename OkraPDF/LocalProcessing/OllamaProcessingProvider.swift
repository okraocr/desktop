import Foundation

/// Generic vision-model provider backed by Ollama's documented localhost API.
/// Model installation and storage remain entirely owned by Ollama.
final class OllamaProcessingProvider: LocalProcessingProvider, OllamaPageParsing, @unchecked Sendable {
    let descriptor = LocalProviderDescriptor(
        id: .ollama,
        name: "Ollama",
        summary: "Uses a vision model already installed in your local Ollama service.",
        setupNote: "Okra connects only to Ollama at localhost. Choose any installed model that reports vision capability.",
        parserDefinition: LocalParserCatalog.ollama
    )

    private let client: OllamaClient
    private let integration: OllamaIntegrationState
    private let lockRoot: URL

    init(
        client: OllamaClient = OllamaClient(),
        integration: OllamaIntegrationState = OllamaIntegrationState(selectedModelName: nil)
    ) {
        self.client = client
        self.integration = integration
        lockRoot = LocalProviderPaths.providersRoot
            .appendingPathComponent("ollama", isDirectory: true)
    }

    func availability() -> LocalProviderAvailability {
        let snapshot = integration.snapshot()
        switch snapshot.connection {
        case .idle:
            return .setupRequired("Connect to Ollama and choose an installed vision model.")
        case .refreshing:
            return .setupRequired("Checking Ollama for installed vision models…")
        case .unavailable(let message):
            return .setupRequired(message)
        case .connected:
            let visionModels = snapshot.models.filter(\.supportsVision)
            guard visionModels.isEmpty == false else {
                return .setupRequired("No installed Ollama models report vision capability.")
            }
            guard let selected = snapshot.selectedModelName,
                  visionModels.contains(where: { $0.name == selected }) else {
                return .setupRequired("Choose an installed Ollama vision model.")
            }
            return .ready
        }
    }

    func process(
        request: LocalProcessingRequest,
        progress: @escaping LocalProcessingProgress
    ) async throws -> LocalProcessingResult {
        try await prepareForParsing()

        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: request.outputDirectory,
                withIntermediateDirectories: true
            )
            let pagesDirectory = request.outputDirectory.appendingPathComponent(
                "pages",
                isDirectory: true
            )
            let pageURLs = try PDFPageRenderer.writePagePNGs(
                from: request.sourceURL,
                to: pagesDirectory,
                maxDimension: 2_048,
                progress: progress
            )
            let pageStore = LocalPageCheckpointStore(
                outputDirectory: request.outputDirectory,
                totalPages: pageURLs.count,
                documentHeader: "# \(request.fileName)"
            )
            try pageStore.prepare()
            var structuredPages: [StructuredExtractionPage] = []

            for (index, pageURL) in pageURLs.enumerated() {
                try Task.checkCancellation()
                let pageNumber = index + 1
                if try pageStore.status(pageNumber: pageNumber) == .succeeded,
                   let page = try? StructuredExtractionPersistence.loadPage(
                       from: pageStore.pagesDirectory,
                       pageNumber: pageNumber
                   ) {
                    structuredPages.append(page)
                    let manifest = try pageStore.reconcileCompletedPages()
                    request.pageProgress(
                        LocalPageProgressUpdate(
                            parserID: request.parserID,
                            pageNumber: pageNumber,
                            state: .done,
                            completedPageCount: manifest.completedPageCount,
                            totalPageCount: pageURLs.count,
                            message: "Restored page \(pageNumber) of \(pageURLs.count) from disk"
                        )
                    )
                    progress(
                        Double(manifest.completedPageCount) / Double(pageURLs.count),
                        "Restored page \(pageNumber) of \(pageURLs.count) from disk"
                    )
                    continue
                }

                let progressManifest = try pageStore.reconcileCompletedPages()
                try pageStore.markProcessing(pageNumber: pageNumber)
                request.pageProgress(
                    LocalPageProgressUpdate(
                        parserID: request.parserID,
                        pageNumber: pageNumber,
                        state: .inProgress,
                        completedPageCount: progressManifest.completedPageCount,
                        totalPageCount: pageURLs.count,
                        message: "Parsing page \(pageNumber) of \(pageURLs.count) with Ollama"
                    )
                )
                do {
                    progress(
                        Double(index) / Double(pageURLs.count),
                        "Sending page \(pageNumber) of \(pageURLs.count) to Ollama"
                    )
                    let parsed = try await self.parsePage(
                        request: OllamaPageParsingRequest(
                            pageNumber: pageNumber,
                            imageURL: pageURL
                        ),
                        progress: { _, message in
                            progress(Double(index) / Double(pageURLs.count), message)
                        }
                    )
                    try StructuredExtractionPersistence.write(
                        page: parsed.structuredPage,
                        to: pageStore.pagesDirectory
                    )
                    try pageStore.writePage(
                        pageNumber: pageNumber,
                        markdown: "## Page \(pageNumber)\n\n\(parsed.markdown)"
                    )
                    structuredPages.append(parsed.structuredPage)
                    let manifest = try pageStore.reconcileCompletedPages()
                    request.pageProgress(
                        LocalPageProgressUpdate(
                            parserID: request.parserID,
                            pageNumber: pageNumber,
                            state: .done,
                            completedPageCount: manifest.completedPageCount,
                            totalPageCount: pageURLs.count,
                            message: "Saved page \(pageNumber) of \(pageURLs.count)"
                        )
                    )
                    progress(
                        Double(manifest.completedPageCount) / Double(pageURLs.count),
                        "Saved page \(pageNumber) of \(pageURLs.count)"
                    )
                } catch is CancellationError {
                    let completed = (try? pageStore.reconcileCompletedPages().completedPageCount) ?? 0
                    request.pageProgress(
                        LocalPageProgressUpdate(
                            parserID: request.parserID,
                            pageNumber: pageNumber,
                            state: .attention,
                            completedPageCount: completed,
                            totalPageCount: pageURLs.count,
                            message: "Canceled. Resume to continue page \(pageNumber)."
                        )
                    )
                    throw CancellationError()
                } catch {
                    try? pageStore.markFailed(pageNumber: pageNumber, error: error)
                    let completed = (try? pageStore.reconcileCompletedPages().completedPageCount) ?? 0
                    request.pageProgress(
                        LocalPageProgressUpdate(
                            parserID: request.parserID,
                            pageNumber: pageNumber,
                            state: .error,
                            completedPageCount: completed,
                            totalPageCount: pageURLs.count,
                            message: error.localizedDescription
                        )
                    )
                    throw error
                }
            }

            let outputURL = try pageStore.assembleResult()
            let structuredOutputURL = outputURL
                .deletingPathExtension()
                .appendingPathExtension("json")
            try StructuredExtractionPersistence.write(
                document: StructuredExtractionDocument(
                    schemaVersion: 1,
                    object: "local_extraction",
                    provider: StructuredExtractionProvider(
                        id: LocalProviderID.ollama.rawValue,
                        name: "Ollama"
                    ),
                    title: request.fileName,
                    pageCount: pageURLs.count,
                    completedPageCount: structuredPages.count,
                    complete: structuredPages.count == pageURLs.count,
                    simulation: false,
                    pages: structuredPages.sorted { $0.pageNumber < $1.pageNumber }
                ),
                to: structuredOutputURL
            )
            progress(1, "Extraction complete")
            return LocalProcessingResult(
                outputURL: outputURL,
                pageCount: pageURLs.count,
                structuredOutputURL: structuredOutputURL
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    func prepareForParsing() async throws {
        let snapshot = integration.snapshot()
        guard let selectedModelName = snapshot.selectedModelName else {
            throw LocalProcessingError.providerUnavailable(
                "Choose an installed Ollama vision model before extracting."
            )
        }
        let detail = try await client.showModel(named: selectedModelName)
        guard detail.capabilities?.contains("vision") == true else {
            throw LocalProcessingError.providerUnavailable(
                "The selected Ollama model no longer reports vision capability. Refresh models and choose another."
            )
        }
    }

    func parsePage(
        request: OllamaPageParsingRequest,
        progress: @escaping LocalProcessingProgress
    ) async throws -> OllamaPageParsingResult {
        guard let model = integration.snapshot().selectedModelName else {
            throw LocalProcessingError.providerUnavailable(
                "Choose an installed Ollama vision model before extracting."
            )
        }

        try FileManager.default.createDirectory(at: lockRoot, withIntermediateDirectories: true)
        let runGate = LocalExclusiveFileLock(url: lockRoot.appendingPathComponent("worker.lock"))
        try await runGate.acquire {
            progress(0, "Waiting for another Ollama request to finish…")
        }
        defer { runGate.release() }

        progress(0, "Parsing page \(request.pageNumber) with \(model)…")
        let markdown = try await client.extractMarkdown(model: model, imageURL: request.imageURL)
        let structuredPage = Self.structuredPage(
            pageNumber: request.pageNumber,
            imageFile: request.imageURL.lastPathComponent,
            markdown: markdown,
            model: model
        )
        return OllamaPageParsingResult(markdown: markdown, structuredPage: structuredPage)
    }

    private static func structuredPage(
        pageNumber: Int,
        imageFile: String,
        markdown: String,
        model: String
    ) -> StructuredExtractionPage {
        StructuredExtractionPage(
            pageNumber: pageNumber,
            imageFile: imageFile,
            markdown: markdown,
            plainText: markdown,
            blocks: [
                StructuredExtractionBlock(
                    id: "page-\(pageNumber)-block-1",
                    type: "text",
                    sourceType: "ollama:\(model)",
                    text: markdown,
                    bbox: nil,
                    sourceBbox: nil,
                    sourceBboxScale: nil
                ),
            ],
            diagnostics: StructuredExtractionDiagnostics(
                rawCharacterCount: markdown.count,
                decodedCharacterCount: markdown.count,
                tokenArtifactCount: 0,
                detectionCount: 1,
                malformedDetectionCount: 0,
                duplicateBlockCount: 0,
                loopDetected: false,
                warnings: []
            )
        )
    }
}
