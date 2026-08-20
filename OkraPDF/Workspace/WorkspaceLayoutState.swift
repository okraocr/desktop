struct WorkspaceLayoutState: Equatable {
    private(set) var prefersSidebarPresented = true
    private(set) var prefersInspectorPresented = false
    private var compactPanel: WorkspacePanel? = .sidebar

    func presentation(for availableWidth: Double) -> WorkspacePresentation {
        guard availableWidth < WorkspaceTheme.compactWidthBreakpoint else {
            return WorkspacePresentation(
                isSidebarPresented: prefersSidebarPresented,
                isInspectorPresented: prefersInspectorPresented
            )
        }

        switch compactPanel {
        case .sidebar where prefersSidebarPresented:
            return WorkspacePresentation(
                isSidebarPresented: true,
                isInspectorPresented: false
            )
        case .inspector where prefersInspectorPresented:
            return WorkspacePresentation(
                isSidebarPresented: false,
                isInspectorPresented: true
            )
        default:
            return WorkspacePresentation(
                isSidebarPresented: false,
                isInspectorPresented: false
            )
        }
    }

    /// Presents a panel regardless of its current state. Compact layouts show
    /// one panel at a time, so this takes the slot from the other one.
    mutating func present(_ panel: WorkspacePanel, availableWidth: Double) {
        guard presentation(for: availableWidth).isPresented(panel) == false else { return }
        toggle(panel, availableWidth: availableWidth)
    }

    mutating func toggle(_ panel: WorkspacePanel, availableWidth: Double) {
        let currentPresentation = presentation(for: availableWidth)

        if availableWidth < WorkspaceTheme.compactWidthBreakpoint {
            switch panel {
            case .sidebar:
                if currentPresentation.isSidebarPresented {
                    prefersSidebarPresented = false
                    compactPanel = nil
                } else {
                    prefersSidebarPresented = true
                    compactPanel = .sidebar
                }
            case .inspector:
                if currentPresentation.isInspectorPresented {
                    prefersInspectorPresented = false
                    compactPanel = nil
                } else {
                    prefersInspectorPresented = true
                    compactPanel = .inspector
                }
            }
            return
        }

        switch panel {
        case .sidebar:
            prefersSidebarPresented.toggle()
            if prefersSidebarPresented {
                compactPanel = .sidebar
            } else if compactPanel == .sidebar {
                compactPanel = prefersInspectorPresented ? .inspector : nil
            }
        case .inspector:
            prefersInspectorPresented.toggle()
            if prefersInspectorPresented {
                compactPanel = .inspector
            } else if compactPanel == .inspector {
                compactPanel = prefersSidebarPresented ? .sidebar : nil
            }
        }
    }
}

struct WorkspacePresentation: Equatable {
    let isSidebarPresented: Bool
    let isInspectorPresented: Bool

    func isPresented(_ panel: WorkspacePanel) -> Bool {
        switch panel {
        case .sidebar:
            return isSidebarPresented
        case .inspector:
            return isInspectorPresented
        }
    }
}
