import AppKit
import Combine
import Foundation
import OkraClientCore
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var selectedDocument: LocalPDFDocument?
    @Published var importError: String?
    @Published private(set) var canOpenPDF = true
    @Published var showsSetupGuide = false

    static let setupGuideCompletedDefaultsKey = "localProcessing.setupGuide.completed"

    let localProcessing: LocalProcessingCoordinator
    private let userDefaults: UserDefaults
    private var clientHost: DesktopClientHTTPHost?
    private var handledClientCallbackNonces: Set<String> = []

    init() {
        let userDefaults = UserDefaults.standard
        self.userDefaults = userDefaults
        localProcessing = LocalProcessingCoordinator()
        bindLocalProcessingState()
        openCommandLinePDFIfPresent()
        showsSetupGuide = userDefaults.object(forKey: Self.setupGuideCompletedDefaultsKey) == nil
        ShellCaptureHarness.startIfRequested(state: self)
        startClientHost()
        openCommandLineClientCallbackIfPresent()
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
        localProcessing.load(document: document)
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme == OkraClientCallback.scheme,
              url.host == OkraClientCallback.host else {
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

    private func openCommandLineClientCallbackIfPresent() {
        guard let callbackURL = ProcessInfo.processInfo.arguments
            .dropFirst()
            .compactMap({ URL(string: $0) })
            .first(where: {
                $0.scheme == OkraClientCallback.scheme
                    && $0.host == OkraClientCallback.host
            }) else {
            return
        }
        deliverClientEndpoint(for: callbackURL)
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

    private func startClientHost() {
        let router = DesktopClientRouter(appState: self)
        let host = DesktopClientHTTPHost(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "1.0.0-rc.15",
            route: { request in await router.route(request) }
        )
        do {
            try host.start()
            clientHost = host
        } catch {
            importError = "The local CLI endpoint could not start: \(error.localizedDescription)"
        }
    }

    private func deliverClientEndpoint(for url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let portValue = components.queryItems?.first(where: { $0.name == "port" })?.value,
              let port = UInt16(portValue),
              port > 0,
              let nonce = components.queryItems?.first(where: { $0.name == "nonce" })?.value,
              nonce.count == 64,
              nonce.allSatisfy({ $0.isHexDigit }),
              handledClientCallbackNonces.insert(nonce).inserted,
              let callbackURL = URL(
                string: "http://127.0.0.1:\(port)\(OkraClientCallback.path)"
              ) else {
            importError = "The local CLI callback was invalid."
            return
        }

        Task {
            guard let endpoint = await waitForClientEndpoint() else {
                importError = "The local CLI endpoint was not ready."
                return
            }
            var request = URLRequest(url: callbackURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("Bearer \(nonce)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(OkraClientProtocol.version, forHTTPHeaderField: OkraClientProtocol.header)
            request.httpBody = try ClientJSON.encoder().encode(endpoint)
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
            } catch {
                importError = "The local CLI callback could not complete."
            }
        }
    }

    private func waitForClientEndpoint() async -> ClientEndpointRecord? {
        for _ in 0..<50 {
            if let endpoint = clientHost?.endpointRecord() { return endpoint }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
