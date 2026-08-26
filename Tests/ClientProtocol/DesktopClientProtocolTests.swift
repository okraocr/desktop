import AppKit
import Foundation
import PDFKit
import Testing
@testable import Okra

@MainActor
struct DesktopClientProtocolTests {
    @Test("Document registration is read-only and parsing yields canonical artifacts")
    func documentParseLifecycle() async throws {
        let workspace = try TestWorkspace(prefix: "okra-client-protocol")
        let source = workspace.root.appendingPathComponent("fixture.pdf")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        try makePDF(text: "Client protocol fixture").write(to: source)
        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let state = AppState(localProcessing: coordinator)
        let router = DesktopClientProtocolRouter(state: state, appVersion: "1.0.0-rc.13")

        let created = router.route(request(
            method: "POST",
            path: "/document",
            body: ["source": source.path]
        ))
        #expect(created.status == 201)
        #expect(coordinator.latestRun == nil)
        let document = try JSONDecoder().decode(TestDocument.self, from: created.body)
        #expect(document.source == source.path)

        let started = router.route(request(
            method: "POST",
            path: "/document/\(document.id)/parse",
            body: ["parserId": LocalProviderID.appleVision.rawValue]
        ))
        #expect(started.status == 202)
        let run = try JSONDecoder().decode(TestRun.self, from: started.body)
        try await waitUntil("client protocol fixture parse") { coordinator.isRunning == false }

        let snapshot = router.route(request(method: "GET", path: "/run/\(run.id)"))
        #expect(snapshot.status == 200)
        #expect(try JSONDecoder().decode(TestRun.self, from: snapshot.body).status == "succeeded")

        let artifacts = router.route(request(method: "GET", path: "/run/\(run.id)/artifacts"))
        #expect(artifacts.status == 200)
        let artifactJSON = try #require(
            JSONSerialization.jsonObject(with: artifacts.body) as? [String: Any]
        )
        #expect(artifactJSON["markdown"] as? String == "# Parsed\n")
        #expect((artifactJSON["manifest"] as? [String: Any])?["parserId"] as? String == "apple-vision")

        let events = router.route(request(method: "GET", path: "/run/\(run.id)/events"))
        let eventText = String(decoding: events.body, as: UTF8.self)
        #expect(eventText.contains("event: run.completed"))
        #expect(eventText.contains("\"artifacts\""))
    }

    @Test("Loopback host requires its endpoint token")
    func loopbackAuthentication() async throws {
        let workspace = try TestWorkspace(prefix: "okra-client-auth")
        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let state = AppState(localProcessing: coordinator)
        let endpointURL = workspace.root.appendingPathComponent("cli-endpoint.json")
        let host = DesktopClientProtocolHost(
            router: DesktopClientProtocolRouter(state: state),
            endpointStateURL: endpointURL
        )
        try host.start()
        defer { host.stop() }
        let endpoint = try #require(host.endpointState)
        let url = try #require(URL(string: "http://127.0.0.1:\(endpoint.port)/global/health"))

        let (_, unauthorizedResponse) = try await URLSession.shared.data(from: url)
        let unauthorizedHTTP = try #require(unauthorizedResponse as? HTTPURLResponse)
        #expect(unauthorizedHTTP.statusCode == 401)

        var authorized = URLRequest(url: url)
        authorized.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        let (data, authorizedResponse) = try await URLSession.shared.data(for: authorized)
        let authorizedHTTP = try #require(authorizedResponse as? HTTPURLResponse)
        #expect(authorizedHTTP.statusCode == 200)
        #expect(authorizedHTTP.value(forHTTPHeaderField: DesktopClientProtocol.header) == DesktopClientProtocol.version)
        #expect((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["healthy"] as? Bool == true)

        let permissions = try FileManager.default.attributesOfItem(atPath: endpointURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test("Catalog marks Chandra OCR 2 as the clean-install default")
    func chandraCatalogDefault() throws {
        let workspace = try TestWorkspace(prefix: "okra-client-catalog")
        let chandra = ChandraOCRProcessingProvider(
            environment: ["OKRA_DESKTOP_SIMULATE_CHANDRA_OCR": "1"]
        )
        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider(), chandra],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let state = AppState(localProcessing: coordinator)
        let router = DesktopClientProtocolRouter(state: state)
        let response = router.route(request(method: "GET", path: "/parser"))
        let root = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let data = try #require(root["data"] as? [[String: Any]])
        let catalogEntry = try #require(data.first { $0["id"] as? String == "chandra-ocr-2" })
        #expect(catalogEntry["isDefault"] as? Bool == true)
        #expect(coordinator.selectedProviderID == .chandraOCR2)
    }

    private func request(
        method: String,
        path: String,
        body: [String: String] = [:]
    ) -> DesktopHTTPRequest {
        DesktopHTTPRequest(
            method: method,
            target: path,
            headers: [:],
            body: (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        )
    }

    private func makePDF(text: String) throws -> Data {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 72, y: 640, width: 468, height: 60)
        view.addSubview(label)
        return view.dataWithPDF(inside: view.bounds)
    }
}

private struct TestDocument: Decodable {
    let id: String
    let source: String
}

private struct TestRun: Decodable {
    let id: String
    let status: String
}
