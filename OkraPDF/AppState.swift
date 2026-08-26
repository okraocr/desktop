import AppKit
import Combine
import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var selectedDocument: LocalPDFDocument?
    @Published private(set) var selectedDocumentOpenedAt: Date?
    @Published var importError: String?
    @Published private(set) var canOpenPDF = true
    @Published var showsSetupGuide = false
    @Published private(set) var clientProtocolError: String?

    static let setupGuideCompletedDefaultsKey = "localProcessing.setupGuide.completed"

    let localProcessing: LocalProcessingCoordinator
    let conversation = AssistantConversation()
    private let userDefaults: UserDefaults
    private var clientProtocolHost: DesktopClientProtocolHost?

    init() {
        let userDefaults = UserDefaults.standard
        self.userDefaults = userDefaults
        localProcessing = LocalProcessingCoordinator()
        bindLocalProcessingState()
        openCommandLinePDFIfPresent()
        showsSetupGuide = userDefaults.object(forKey: Self.setupGuideCompletedDefaultsKey) == nil
        startClientProtocolHost()
        ShellCaptureHarness.startIfRequested(state: self)
    }

    init(localProcessing: LocalProcessingCoordinator) {
        self.localProcessing = localProcessing
        self.userDefaults = .standard
        bindLocalProcessingState()
    }

    func presentSetupGuide() {
        showsSetupGuide = true
    }

    func dismissSetupGuide() {
        showsSetupGuide = false
        userDefaults.set(true, forKey: Self.setupGuideCompletedDefaultsKey)
    }


    func openPDFPicker() {
        guard canOpenPDF else {
            importError = activeOperationMessage
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Open PDF"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openPDF(url)
    }

    func openPDF(_ url: URL) {
        guard canOpenPDF else {
            importError = activeOperationMessage
            return
        }

        importError = nil

        guard url.isFileURL, url.pathExtension.lowercased() == UTType.pdf.preferredFilenameExtension else {
            importError = "Choose a PDF file."
            return
        }

        let normalizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: normalizedURL.path),
              let pdf = PDFDocument(url: normalizedURL),
              pdf.pageCount > 0 else {
            importError = "Could not open \(url.lastPathComponent)."
            return
        }

        let document = LocalPDFDocument(
            id: normalizedURL.path,
            fileName: normalizedURL.lastPathComponent,
            filePath: normalizedURL.path,
            totalPages: pdf.pageCount
        )
        selectedDocument = document
        selectedDocumentOpenedAt = .now
        localProcessing.load(document: document)
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme == DesktopClientCallback.scheme,
              url.host == DesktopClientCallback.host else {
            openPDF(url)
            return
        }
        deliverClientEndpoint(for: url)
    }

    func parseSelectedDocument() {
        guard let selectedDocument else { return }
        localProcessing.run(document: selectedDocument)
    }

    func openRun(_ run: LocalProcessingRun) {
        guard canOpenPDF else {
            importError = activeOperationMessage
            return
        }

        let sourceURL = URL(fileURLWithPath: run.sourcePath).standardizedFileURL
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            openPDF(sourceURL)
        } else {
            importError = "The original PDF for \(run.fileName) is no longer at \(run.sourcePath)."
        }
        localProcessing.selectRun(run)
    }

    func revealSelectedPDF() {
        guard let selectedDocument else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            selectedDocument.fileURL,
        ])
    }

    func dismissImportError() {
        importError = nil
    }

    func copyLocalParserDiagnostics() {
        localProcessing.copyDoctorReport()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func openCommandLinePDFIfPresent() {
        guard let path = ProcessInfo.processInfo.arguments
            .dropFirst()
            .first(where: { $0.lowercased().hasSuffix(".pdf") }) else {
            return
        }
        openPDF(URL(fileURLWithPath: path))
    }

    private var activeOperationMessage: String {
        "Finish or cancel the active local operation before opening another PDF."
    }

    private func bindLocalProcessingState() {
        localProcessing.$isRunning
            .combineLatest(localProcessing.$isInstalling)
            .combineLatest(localProcessing.redaction.$isInstalling)
            .combineLatest(localProcessing.redaction.$isDetecting)
            .combineLatest(localProcessing.redaction.$isExporting)
            .map { values, isExporting in
                let (((isRunning, isInstalling), isRedactionInstalling), isDetecting) = values
                return isRunning == false
                    && isInstalling == false
                    && isRedactionInstalling == false
                    && isDetecting == false
                    && isExporting == false
            }
            .removeDuplicates()
            .assign(to: &$canOpenPDF)
    }

    private func startClientProtocolHost() {
        let host = DesktopClientProtocolHost(
            router: DesktopClientProtocolRouter(state: self)
        )
        do {
            try host.start()
            clientProtocolHost = host
        } catch {
            clientProtocolError = error.localizedDescription
        }
    }

    private func deliverClientEndpoint(for url: URL) {
        guard let endpoint = clientProtocolHost?.endpointState,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let portValue = components.queryItems?.first(where: { $0.name == "port" })?.value,
              let port = UInt16(portValue),
              port > 0,
              let nonce = components.queryItems?.first(where: { $0.name == "nonce" })?.value,
              nonce.count >= 32,
              nonce.allSatisfy({ $0.isHexDigit }),
              let callbackURL = URL(string: "http://127.0.0.1:\(port)/endpoint") else {
            clientProtocolError = "The local CLI callback was invalid."
            return
        }

        var request = URLRequest(url: callbackURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(nonce)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(endpoint)
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
            } catch {
                clientProtocolError = "The local CLI callback could not complete."
            }
        }
    }
}
