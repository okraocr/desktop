import Foundation

/// Activity is local workspace history, not an installable plugin.
enum WorkspaceActivity: String, CaseIterable, Identifiable {
    case runs

    var id: String { rawValue }

    var name: String { "Runs" }

    var systemImage: String { "clock.arrow.circlepath" }

    var summary: String { "Recent local runs and outputs" }

    var command: String { "/runs" }
}

enum WorkspaceNavigationSection: String, Equatable {
    case plugins = "Plugins"
    case activity = "Activity"
}

/// A stable left-navigation destination. The enum makes the plugin/activity
/// boundary explicit so activity can never leak into plugin iteration again.
enum WorkspaceNavigationDestination: Identifiable, Equatable {
    case plugin(AssistantPlugin)
    case activity(WorkspaceActivity)

    var id: String {
        switch self {
        case .plugin(let plugin):
            return "plugin.\(plugin.id)"
        case .activity(let activity):
            return "activity.\(activity.id)"
        }
    }

    var section: WorkspaceNavigationSection {
        switch self {
        case .plugin:
            return .plugins
        case .activity:
            return .activity
        }
    }

    var name: String {
        switch self {
        case .plugin(let plugin):
            return plugin.name
        case .activity(let activity):
            return activity.name
        }
    }

    var systemImage: String {
        switch self {
        case .plugin(let plugin):
            return plugin.systemImage
        case .activity(let activity):
            return activity.systemImage
        }
    }

    var summary: String {
        switch self {
        case .plugin(let plugin):
            return plugin.summary
        case .activity(let activity):
            return activity.summary
        }
    }
}
