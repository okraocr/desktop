import Testing
@testable import Okra

@Suite("Parser panel rows")
struct ParserPluginItemTests {
    private func descriptor(_ id: LocalProviderID, _ name: String) -> LocalProviderDescriptor {
        LocalProviderDescriptor(
            id: id,
            name: name,
            summary: "\(name) summary",
            setupNote: nil
        )
    }

    private var descriptors: [LocalProviderDescriptor] {
        [
            descriptor(.appleVision, "Apple Vision"),
            descriptor(.chandraOCR2, "Chandra OCR")
        ]
    }

    @Test("Each availability case maps to the readiness the row draws")
    func readinessMapping() {
        #expect(ParserPluginItem.readiness(for: .ready) == .ready)
        #expect(ParserPluginItem.readiness(for: .simulated("Simulated")) == .simulated)
        #expect(ParserPluginItem.readiness(for: .setupRequired("Download first")) == .needsSetup)
        #expect(ParserPluginItem.readiness(for: .unavailable("No GPU")) == .unavailable)
        // A provider we have not probed yet is not offered as runnable.
        #expect(ParserPluginItem.readiness(for: nil) == .unavailable)
    }

    @Test("Rows carry the availability line, the badge, and the selection")
    func rowsCarryStatusBadgeAndSelection() {
        let items = ParserPluginItem.items(
            descriptors: descriptors,
            availability: [
                .appleVision: .ready,
                .chandraOCR2: .setupRequired("Download the model to use Chandra")
            ],
            badges: [.appleVision: .fastest],
            selected: .chandraOCR2
        )

        #expect(items.count == 2)

        let vision = items[0]
        #expect(vision.name == "Apple Vision")
        #expect(vision.statusMessage == "Ready offline")
        #expect(vision.badge == .fastest)
        #expect(vision.isRunnable)
        #expect(vision.canInstall == false)
        #expect(vision.isSelected == false)

        let chandra = items[1]
        #expect(chandra.statusMessage == "Download the model to use Chandra")
        #expect(chandra.badge == nil)
        #expect(chandra.isRunnable == false)
        #expect(chandra.canInstall)
        #expect(chandra.isSelected)
    }

    @Test("Rows keep descriptor order so installing a model cannot reshuffle the list")
    func rowsKeepDescriptorOrder() {
        let items = ParserPluginItem.items(
            descriptors: descriptors,
            availability: [
                .appleVision: .setupRequired("Needs setup"),
                .chandraOCR2: .ready
            ],
            badges: [:],
            selected: .appleVision
        )

        #expect(items.map(\.id) == descriptors.map(\.id))
    }

    @Test("A row describes itself for VoiceOver without relying on the status icon")
    func accessibilityDescriptionNamesBadgeAndStatus() {
        let items = ParserPluginItem.items(
            descriptors: [descriptor(.appleVision, "Apple Vision")],
            availability: [.appleVision: .ready],
            badges: [.appleVision: .recommendedForThisMac],
            selected: .appleVision
        )

        #expect(
            items[0].accessibilityDescription
                == "Apple Vision, Recommended for this Mac, Ready offline"
        )
    }
}
