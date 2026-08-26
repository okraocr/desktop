import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PresidioRedactionCoordinator: ObservableObject {
    @Published private(set) var availability: LocalProviderAvailability = .setupRequired(
        "Microsoft Presidio 2.2.364 + English spaCy model"
    )
    @Published private(set) var detection: RedactionDetection?
    @Published private(set) var approvedBoxIDs: Set<String> = []
    @Published private(set) var selectedBoxID: String?
    @Published private(set) var hoveredBoxID: String?
    @Published private(set) var statusMessage = "Detect PII only after reviewing a positioned extraction."
    @Published private(set) var errorMessage: String?
    @Published private(set) var isInstalling = false
    @Published private(set) var setupProgress: LocalProviderSetupProgress?
    @Published private(set) var isDetecting = false
    @Published private(set) var isExporting = false
    @Published var usesOllama: Bool {
        didSet { userDefaults.set(usesOllama, forKey: Self.usesOllamaDefaultsKey) }
    }
    @Published var selectedOllamaModelName: String? {
        didSet {
            if let selectedOllamaModelName {
                userDefaults.set(
                    selectedOllamaModelName,
                    forKey: Self.ollamaModelDefaultsKey
                )
            } else {
                userDefaults.removeObject(forKey: Self.ollamaModelDefaultsKey)
            }
        }
    }

    private static let usesOllamaDefaultsKey = "redaction.presidio.usesOllama"
    private static let ollamaModelDefaultsKey = "redaction.presidio.ollamaModel"

    private let service: any PresidioRedactionServicing
    private let userDefaults: UserDefaults
    private var currentRun: LocalProcessingRun?
    private var currentDocument: StructuredExtractionDocument?
    private var currentSourceURL: URL?
    private var availabilityTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?

    init(
        service: any PresidioRedactionServicing = PresidioRedactionService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.userDefaults = userDefaults
        usesOllama = userDefaults.bool(forKey: Self.usesOllamaDefaultsKey)
        selectedOllamaModelName = userDefaults.string(forKey: Self.ollamaModelDefaultsKey)
        refreshAvailability()
    }

    deinit {
        availabilityTask?.cancel()
        installTask?.cancel()
        detectionTask?.cancel()
        let service = service
        Task { await service.shutdown() }
    }

    var isBusy: Bool {
        isInstalling || isDetecting || isExporting
    }

    var isManaged: Bool {
        ProcessInfo.processInfo.environment["OKRA_PRESIDIO_URL"] == nil
    }

    var ollamaSupported: Bool { isManaged }

    var hasPositionedBlocks: Bool {
        currentDocument?.pages.contains { page in
            page.blocks.contains { block in
                block.bbox?.clippedNormalizedRect != nil
                    && block.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        } == true
    }

    var canDetect: Bool {
        availability.isReady
            && hasPositionedBlocks
            && isBusy == false
            && currentRun?.status == "succeeded"
            && (!usesOllama || selectedOllamaModelName?.isEmpty == false)
    }

    var approvedBoxes: [RedactionBox] {
        detection?.boxes.filter { approvedBoxIDs.contains($0.id) } ?? []
    }

    var pdfOverlays: [PDFBoundingBoxOverlay] {
        approvedBoxes.map(\.pdfOverlay)
    }

    func load(
        run: LocalProcessingRun?,
        structuredDocument: StructuredExtractionDocument?,
        sourceURL: URL?
    ) {
        currentRun = run
        currentDocument = structuredDocument
        currentSourceURL = sourceURL
        selectedBoxID = nil
        hoveredBoxID = nil
        errorMessage = nil

        guard let run,
              run.status == "succeeded",
              structuredDocument != nil else {
            detection = nil
            approvedBoxIDs = []
            statusMessage = "Complete a positioned parse before detecting PII."
            return
        }
        let cachedURL = redactionsURL(for: run)
        if let cached = try? RedactionDetection.load(from: cachedURL),
           cached.runID == run.id {
            detection = cached
            approvedBoxIDs = Set(cached.boxes.map(\.id))
            statusMessage = cached.boxes.isEmpty
                ? "Presidio found no PII candidates."
                : "Review \(cached.boxes.count) cached PII candidates before export."
        } else {
            detection = nil
            approvedBoxIDs = []
            statusMessage = hasPositionedBlocks
                ? "Ready to detect PII locally."
                : "This extraction has no positioned blocks."
        }
    }

    func refreshAvailability() {
        availabilityTask?.cancel()
        availabilityTask = Task { [weak self] in
            guard let self else { return }
            let availability = await service.availability()
            guard Task.isCancelled == false else { return }
            self.availability = availability
            self.availabilityTask = nil
        }
    }

    func install() {
        guard isManaged, isBusy == false else { return }
        isInstalling = true
        errorMessage = nil
        let initialProgress = LocalProviderSetupProgress(
            phase: .preparing,
            fraction: nil,
            message: "Preparing the Presidio plugin…"
        )
        setupProgress = initialProgress
        statusMessage = initialProgress.message
        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.install { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.isInstalling else { return }
                        self.setupProgress = update
                        self.statusMessage = update.message
                    }
                }
                availability = await service.availability()
                statusMessage = "Microsoft Presidio is ready locally."
            } catch is CancellationError {
                statusMessage = "Presidio setup canceled. You can restart it from Plugins."
            } catch {
                let diagnostic = LocalErrorPresentation.diagnosticDescription(for: error)
                errorMessage = diagnostic
                statusMessage = diagnostic
                availability = await service.availability()
            }
            isInstalling = false
            setupProgress = nil
            installTask = nil
        }
    }

    func cancelInstallation() {
        guard isInstalling else { return }
        statusMessage = "Canceling Presidio setup…"
        if let setupProgress {
            self.setupProgress = LocalProviderSetupProgress(
                phase: setupProgress.phase,
                fraction: setupProgress.fraction,
                message: statusMessage
            )
        }
        installTask?.cancel()
    }

    func detect() {
        detectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await detectForClient()
            } catch is CancellationError {
                statusMessage = "PII detection canceled."
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
            detectionTask = nil
        }
    }

    func detectForClient(runID: String? = nil) async throws -> RedactionDetection {
        guard canDetect,
              let run = currentRun,
              let document = currentDocument,
              runID == nil || run.id == runID else {
            throw PresidioClientError.unavailable(statusMessage)
        }
        let model = usesOllama ? selectedOllamaModelName : nil
        isDetecting = true
        errorMessage = nil
        selectedBoxID = nil
        hoveredBoxID = nil
        statusMessage = model == nil
            ? "Detecting PII with Presidio on this Mac…"
            : "Detecting PII with Presidio and \(model!) through local Ollama…"
        defer { isDetecting = false }

        do {
            let result = try await service.detect(
                runID: run.id,
                document: document,
                ollamaModel: model,
                redactionsURL: redactionsURL(for: run)
            )
            guard currentRun?.id == run.id else {
                throw PresidioClientError.runChanged
            }
            detection = result
            approvedBoxIDs = Set(result.boxes.map(\.id))
            statusMessage = result.boxes.isEmpty
                ? "Presidio found no PII candidates above the confidence threshold."
                : "Review \(result.boxes.count) PII candidates before export."
            return result
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
            throw error
        }
    }

    func detectionForClient(run: LocalProcessingRun) -> RedactionDetection? {
        if currentRun?.id == run.id, let detection { return detection }
        guard let cached = try? RedactionDetection.load(from: redactionsURL(for: run)),
              cached.runID == run.id else { return nil }
        return cached
    }

    func isDetectingForClient(runID: String) -> Bool {
        currentRun?.id == runID && isDetecting
    }

    func setApproved(_ approved: Bool, for id: String) {
        guard detection?.boxes.contains(where: { $0.id == id }) == true else { return }
        if approved {
            approvedBoxIDs.insert(id)
        } else {
            approvedBoxIDs.remove(id)
            if selectedBoxID == id { selectedBoxID = nil }
            if hoveredBoxID == id { hoveredBoxID = nil }
        }
    }

    func selectBox(_ id: String) {
        guard approvedBoxIDs.contains(id) else { return }
        selectedBoxID = id
    }

    func hoverBox(_ id: String, isHovering: Bool) {
        guard approvedBoxIDs.contains(id) else { return }
        if isHovering {
            hoveredBoxID = id
        } else if hoveredBoxID == id {
            hoveredBoxID = nil
        }
    }

    func hoverPDFOverlay(_ id: String?) {
        guard id == nil || approvedBoxIDs.contains(id!) else { return }
        hoveredBoxID = id
    }

    func export() {
        guard isBusy == false,
              approvedBoxes.isEmpty == false,
              let sourceURL = currentSourceURL else { return }
        let panel = NSSavePanel()
        panel.title = "Export Redacted PDF"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(stem)-redacted.pdf"
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isExporting = true
        errorMessage = nil
        statusMessage = "Rasterizing affected pages and burning in approved redactions…"
        do {
            try RedactedPDFExporter.export(
                sourceURL: sourceURL,
                destinationURL: destination,
                boxes: approvedBoxes
            )
            statusMessage = "Saved redacted PDF without changing the source."
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
        isExporting = false
    }

    private func redactionsURL(for run: LocalProcessingRun) -> URL {
        URL(fileURLWithPath: run.outputPath ?? run.sourcePath)
            .deletingLastPathComponent()
            .appendingPathComponent("redactions.json")
    }
}

private enum PresidioClientError: LocalizedError {
    case unavailable(String)
    case runChanged

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            return "Presidio is not ready for this run. \(detail)"
        case .runChanged:
            return "The selected run changed while Presidio was detecting PII."
        }
    }
}
