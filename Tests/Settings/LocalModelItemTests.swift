import Testing
@testable import Okra

@Suite("Local model settings items")
struct LocalModelItemTests {
    @Test("Settings keeps models and redaction out of the document task modes")
    func settingsSections() {
        #expect(
            DesktopSettingsSection.allCases
                == [.general, .models, .redaction, .advanced, .about]
        )
    }

    @Test("Availability maps to the settings collections")
    func collectionMapping() {
        #expect(LocalModelItem.readiness(for: .ready) == .ready)
        #expect(LocalModelItem.readiness(for: .simulated("Simulated")) == .simulated)
        #expect(LocalModelItem.readiness(for: .setupRequired("Download first")) == .needsSetup)
        #expect(LocalModelItem.readiness(for: .unavailable("No GPU")) == .unavailable)
        #expect(LocalModelItem.readiness(for: nil) == .unavailable)

        #expect(item(readiness: .ready).collection == .installed)
        #expect(item(readiness: .simulated).collection == .installed)
        #expect(item(readiness: .needsSetup).collection == .available)
        #expect(item(readiness: .unavailable).collection == .unavailable)
    }

    @Test("Active and recommended state is announced")
    func accessibilityCopy() {
        let model = LocalModelItem(
            id: .appleVision,
            name: "Apple Vision",
            summary: "Built in",
            statusMessage: "Ready",
            readiness: .ready,
            badge: .recommendedForThisMac,
            isSelected: true,
            downloadSizeBytes: nil
        )

        #expect(model.accessibilityDescription.contains("Recommended for this Mac"))
        #expect(model.accessibilityDescription.contains("Active"))
    }

    private func item(readiness: LocalModelItem.Readiness) -> LocalModelItem {
        LocalModelItem(
            id: .appleVision,
            name: "Apple Vision",
            summary: "Built in",
            statusMessage: "Status",
            readiness: readiness,
            badge: nil,
            isSelected: false,
            downloadSizeBytes: nil
        )
    }
}
