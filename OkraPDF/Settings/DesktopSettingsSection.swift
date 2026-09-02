import AppKit
import Foundation

enum DesktopSettingsSection: String, CaseIterable, Identifiable {
    case general
    case models
    case redaction
    case advanced
    case about

    static let selectionDefaultsKey = "settings.selectedSection"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .models: return "Models"
        case .redaction: return "Redaction"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .models: return "cpu"
        case .redaction: return "eye.slash"
        case .advanced: return "gearshape.2"
        case .about: return "info.circle"
        }
    }
}

@MainActor
enum DesktopSettingsWindow {
    static func open(_ section: DesktopSettingsSection) {
        UserDefaults.standard.set(section.rawValue, forKey: DesktopSettingsSection.selectionDefaultsKey)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let settingsItem = NSApplication.shared.mainMenu?
            .items
            .first?
            .submenu?
            .items
            .first(where: { $0.keyEquivalent == "," }),
           let action = settingsItem.action {
            _ = NSApplication.shared.sendAction(
                action,
                to: settingsItem.target,
                from: settingsItem
            )
            return
        }
        if NSApplication.shared.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        ) == false {
            _ = NSApplication.shared.sendAction(
                Selector(("showPreferencesWindow:")),
                to: nil,
                from: nil
            )
        }
    }
}
