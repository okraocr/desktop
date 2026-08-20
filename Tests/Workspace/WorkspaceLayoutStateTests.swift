import Testing
@testable import Okra

@Suite("Workspace layout state")
struct WorkspaceLayoutStateTests {
    @Test("The reader opens with wayfinding visible and Extract tucked away")
    func defaultLayoutIsDocumentFirst() {
        let layout = WorkspaceLayoutState()
        let presentation = layout.presentation(for: 1_320)

        #expect(presentation.isSidebarPresented)
        #expect(presentation.isInspectorPresented == false)
    }

    @Test("Wide layouts toggle panels independently")
    func widePanelsToggleIndependently() {
        var layout = WorkspaceLayoutState()

        layout.toggle(.inspector, availableWidth: 1_320)
        var presentation = layout.presentation(for: 1_320)
        #expect(presentation.isSidebarPresented)
        #expect(presentation.isInspectorPresented)

        layout.toggle(.sidebar, availableWidth: 1_320)
        presentation = layout.presentation(for: 1_320)
        #expect(presentation.isSidebarPresented == false)
        #expect(presentation.isInspectorPresented)
    }

    @Test("Compact layouts show only the last panel opened")
    func compactPanelsAreMutuallyExclusive() {
        var layout = WorkspaceLayoutState()

        layout.toggle(.inspector, availableWidth: 960)
        var presentation = layout.presentation(for: 960)

        #expect(presentation.isSidebarPresented == false)
        #expect(presentation.isInspectorPresented)

        layout.toggle(.sidebar, availableWidth: 960)
        presentation = layout.presentation(for: 960)
        #expect(presentation.isSidebarPresented)
        #expect(presentation.isInspectorPresented == false)
    }

    @Test("A compact panel can close without opening the opposite panel")
    func compactPanelClosesToReaderOnly() {
        var layout = WorkspaceLayoutState()

        layout.toggle(.sidebar, availableWidth: 960)
        let presentation = layout.presentation(for: 960)

        #expect(presentation.isSidebarPresented == false)
        #expect(presentation.isInspectorPresented == false)
    }

    @Test("Automatic compaction preserves wide preferences")
    func widePreferencesSurviveCompaction() {
        var layout = WorkspaceLayoutState()
        layout.toggle(.inspector, availableWidth: 1_320)

        let compactPresentation = layout.presentation(for: 960)
        #expect(compactPresentation.isSidebarPresented == false)
        #expect(compactPresentation.isInspectorPresented)

        let restoredPresentation = layout.presentation(for: 1_320)
        #expect(restoredPresentation.isSidebarPresented)
        #expect(restoredPresentation.isInspectorPresented)
    }

    @Test("The derived breakpoint enters wide mode at its exact boundary")
    func breakpointBehavior() {
        var layout = WorkspaceLayoutState()
        layout.toggle(.inspector, availableWidth: 1_320)
        let breakpoint = WorkspaceTheme.compactWidthBreakpoint

        let belowBreakpoint = layout.presentation(for: breakpoint - 0.1)
        #expect(belowBreakpoint.isSidebarPresented == false)
        #expect(belowBreakpoint.isInspectorPresented)

        let atBreakpoint = layout.presentation(for: breakpoint)
        #expect(atBreakpoint.isSidebarPresented)
        #expect(atBreakpoint.isInspectorPresented)
    }

    @Test("Asking for Plugins opens the sidebar instead of toggling it shut")
    func presentOpensRatherThanToggles() {
        var layout = WorkspaceLayoutState()

        // Already open: presenting again must be a no-op, not a hide.
        layout.present(.sidebar, availableWidth: 1_320)
        #expect(layout.presentation(for: 1_320).isSidebarPresented)

        layout.toggle(.sidebar, availableWidth: 1_320)
        #expect(layout.presentation(for: 1_320).isSidebarPresented == false)

        layout.present(.sidebar, availableWidth: 1_320)
        #expect(layout.presentation(for: 1_320).isSidebarPresented)
    }

    @Test("In compact widths, opening Plugins takes the slot from Extract")
    func presentTakesTheCompactSlot() {
        var layout = WorkspaceLayoutState()

        layout.toggle(.inspector, availableWidth: 960)
        #expect(layout.presentation(for: 960).isInspectorPresented)

        layout.present(.sidebar, availableWidth: 960)
        let presentation = layout.presentation(for: 960)
        #expect(presentation.isSidebarPresented)
        #expect(presentation.isInspectorPresented == false)
    }
}
