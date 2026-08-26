import Foundation
import OkraClientCore

enum DesktopClientProjection {
    static func document(_ document: LocalPDFDocument, openedAt: Date = .now) -> ClientDocument {
        ClientDocument(
            id: documentID(for: document.filePath),
            title: document.fileName,
            source: document.filePath,
            pageCount: document.totalPages,
            openedAt: timestamp(openedAt)
        )
    }

    static func documentID(for source: String) -> String {
        Data(source.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func provider(
        _ descriptor: LocalProviderDescriptor,
        availability: LocalProviderAvailability,
        selected: Bool
    ) -> ClientProviderSpec {
        let availabilityID: String
        switch availability {
        case .ready: availabilityID = "ready"
        case .simulated: availabilityID = "simulated"
        case .setupRequired: availabilityID = "setup_required"
        case .unavailable: availabilityID = "unavailable"
        }
        let loopback = descriptor.id == .ollama || descriptor.id == .hybridAuto
        let hasModel = descriptor.id != .appleVision && descriptor.id != .hybridAuto
        return ClientProviderSpec(
            id: descriptor.id.rawValue,
            displayName: descriptor.name,
            baseUrl: loopback ? "http://127.0.0.1:11434" : nil,
            defaultModel: hasModel ? descriptor.id.rawValue : nil,
            models: hasModel
                ? [ClientModelSpec(id: descriptor.id.rawValue, displayName: descriptor.name, vision: true)]
                : [],
            keyHint: loopback
                ? "No API key; Okra talks to the local Ollama service."
                : "No API key; runs on this Mac.",
            delivery: loopback ? "loopback" : "on_device",
            availability: availabilityID,
            detail: availability.message,
            selected: selected
        )
    }

    static func parser(_ descriptor: LocalProviderDescriptor) -> ClientParserSpec {
        ClientParserSpec(
            id: descriptor.id.rawValue,
            displayName: descriptor.name,
            version: "1",
            requires: descriptor.id == .ollama || descriptor.id == .hybridAuto ? "http" : "none",
            defaults: ["providerId": descriptor.id.rawValue]
        )
    }

    static func run(_ run: LocalProcessingRun, model: String? = nil) -> ClientRun {
        let status: String
        switch run.status {
        case "canceling": status = "cancelling"
        case "canceled": status = "cancelled"
        case "interrupted": status = "attention"
        default: status = run.status
        }
        let pages = (run.pageLifecycles ?? []).map { lifecycle in
            ClientPageLifecycle(
                parserId: lifecycle.parserID,
                page: lifecycle.pageNumber,
                state: lifecycle.state == .inProgress ? "in_progress" : lifecycle.state.rawValue,
                detail: lifecycle.detail,
                updatedAt: timestamp(lifecycle.updatedAt)
            )
        }
        return ClientRun(
            id: run.id,
            documentId: documentID(for: run.sourcePath),
            parserId: run.providerId,
            providerId: run.providerId,
            model: model,
            status: status,
            pageCount: run.totalPageCount ?? run.pageCount,
            pages: pages,
            createdAt: timestamp(run.startedAt),
            updatedAt: timestamp(run.updatedAt ?? run.completedAt ?? run.startedAt)
        )
    }

    static func artifacts(for run: LocalProcessingRun) throws -> ClientArtifacts {
        guard run.status == "succeeded",
              let outputPath = run.outputPath else {
            throw DesktopClientProjectionError.artifactsUnavailable
        }
        let markdown = try String(contentsOfFile: outputPath, encoding: .utf8)
        let structured = run.structuredOutputPath.flatMap { path in
            try? StructuredExtractionDocument.load(from: URL(fileURLWithPath: path))
        }
        var warnings = structured?.pages.flatMap(\.diagnostics.warnings) ?? []
        let blocks = structured?.pages.flatMap { page in
            page.blocks.compactMap { block -> ClientLayoutBlock? in
                guard let bbox = block.bbox, bbox.unit == "normalized" else { return nil }
                return ClientLayoutBlock(
                    label: canonicalLabel(block.type),
                    bbox: canonicalBbox(bbox),
                    text: block.displayText,
                    page: page.pageNumber
                )
            }
        } ?? []
        let structuredCount = structured?.pages.reduce(0) { $0 + $1.blocks.count } ?? 0
        if structuredCount > blocks.count {
            warnings.append("\(structuredCount - blocks.count) unpositioned blocks were omitted from canonical blocks.json.")
        }
        let duration = (run.completedAt ?? run.updatedAt ?? .now).timeIntervalSince(run.startedAt)
        return ClientArtifacts(
            markdown: markdown,
            blocks: blocks,
            manifest: ClientParseManifest(
                parserId: run.providerId,
                providerId: run.providerId,
                model: run.providerId,
                pageCount: run.pageCount,
                durationMs: max(0, duration * 1_000),
                warnings: Array(Set(warnings)).sorted()
            )
        )
    }

    static func redaction(_ detection: RedactionDetection) -> ClientRedactionDetection {
        ClientRedactionDetection(
            runId: detection.runID,
            model: detection.ollamaModel,
            createdAt: timestamp(detection.createdAt),
            candidates: detection.boxes.map { box in
                let x1 = min(max(box.x * 1_000, 0), 1_000)
                let y1 = min(max(box.y * 1_000, 0), 1_000)
                let x2 = min(max((box.x + box.width) * 1_000, x1), 1_000)
                let y2 = min(max((box.y + box.height) * 1_000, y1), 1_000)
                return ClientRedactionCandidate(
                    id: box.id,
                    type: box.type,
                    text: box.text,
                    score: box.score,
                    source: box.source,
                    page: box.page,
                    bbox: [x1, y1, x2, y2]
                )
            }
        )
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func canonicalBbox(_ bbox: StructuredExtractionBoundingBox) -> [Double] {
        let x1 = min(max(bbox.x * 1_000, 0), 1_000)
        let y1 = min(max(bbox.y * 1_000, 0), 1_000)
        let x2 = min(max((bbox.x + bbox.width) * 1_000, x1), 1_000)
        let y2 = min(max((bbox.y + bbox.height) * 1_000, y1), 1_000)
        return [x1, y1, x2, y2]
    }

    private static func canonicalLabel(_ source: String) -> String {
        switch source.lowercased() {
        case "caption": return "Caption"
        case "footnote": return "Footnote"
        case "formula", "equation": return "Formula"
        case "list", "list-item", "list_item": return "List-item"
        case "page-footer", "footer": return "Page-footer"
        case "page-header", "header": return "Page-header"
        case "picture", "figure", "image": return "Picture"
        case "section-header", "heading", "section_header": return "Section-header"
        case "table": return "Table"
        case "title": return "Title"
        default: return "Text"
        }
    }
}

enum DesktopClientProjectionError: LocalizedError {
    case artifactsUnavailable

    var errorDescription: String? {
        "Artifacts are available after a run succeeds."
    }
}
