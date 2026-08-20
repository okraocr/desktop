import SwiftUI

enum WorkspaceTheme {
    static let brand = Color(red: 31 / 255, green: 122 / 255, blue: 76 / 255)
    static let compactSpacing = 6.0
    static let standardSpacing = 12.0
    static let sectionSpacing = 18.0
    static let panelPadding = 18.0
    static let cardRadius = 10.0
    static let railWidth = 44.0
    static let railControlSize = 32.0
    static let sidebarWidth = 272.0
    static let inspectorWidth = 340.0
    static let readerMinimumWidth = 520.0
    static let layoutDividerAllowance = 2.0
    static let compactWidthBreakpoint = sidebarWidth
        + inspectorWidth
        + (railWidth * 2)
        + readerMinimumWidth
        + layoutDividerAllowance
}
