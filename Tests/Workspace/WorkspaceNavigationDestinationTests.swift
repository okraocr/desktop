import Testing
@testable import Okra

@Suite("Workspace navigation")
struct WorkspaceNavigationDestinationTests {
    @Test("Plugin inventory excludes activity")
    func pluginInventoryExcludesActivity() {
        #expect(AssistantPlugin.allCases == [.extract, .redact])
        #expect(WorkspaceActivity.allCases == [.runs])
    }

    @Test("Destinations retain their navigation section")
    func destinationsRetainTheirSection() {
        #expect(WorkspaceNavigationDestination.plugin(.extract).section == .plugins)
        #expect(WorkspaceNavigationDestination.plugin(.redact).section == .plugins)
        #expect(WorkspaceNavigationDestination.activity(.runs).section == .activity)
    }
}
