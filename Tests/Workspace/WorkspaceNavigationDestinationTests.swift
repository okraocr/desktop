import Testing
@testable import Okra

@Suite("Workspace navigation")
struct WorkspaceNavigationDestinationTests {
    @Test("Plugin inventory excludes activity")
    func pluginInventoryExcludesActivity() {
        #expect(WorkspacePlugin.allCases == [.extract, .redact])
        #expect(WorkspaceActivity.allCases == [.runs])
    }

    @Test("Facet modes remain source-linked workflows")
    func facetModesRemainSourceLinkedWorkflows() {
        #expect(FacetWorkspaceMode.allCases == [.extraction, .redaction])
    }

    @Test("Destinations retain their navigation section")
    func destinationsRetainTheirSection() {
        #expect(WorkspaceNavigationDestination.plugin(.extract).section == .plugins)
        #expect(WorkspaceNavigationDestination.plugin(.redact).section == .plugins)
        #expect(WorkspaceNavigationDestination.activity(.runs).section == .activity)
    }
}
