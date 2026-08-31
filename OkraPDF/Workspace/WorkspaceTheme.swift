import SwiftUI

enum WorkspaceTheme {
    static let brand = Color(red: 31 / 255, green: 122 / 255, blue: 76 / 255)
    static let compactSpacing = 6.0
    static let standardSpacing = 12.0
    static let sectionSpacing = 18.0
    static let panelPadding = 18.0
    static let cardRadius = 10.0
    static let facetMinimumWidth = 360.0
    static let facetIdealWidth = 440.0
    static let navigationPanelWidth = 360.0
    static let readerMinimumWidth = 520.0
}

extension View {
    /// macOS 26 dark mode drops the vibrant label of tinted
    /// `.borderedProminent` buttons composited over a Material background,
    /// leaving a blank pill. Clearing the inherited material opts panel
    /// content out of vibrant text so button labels stay opaque. Attach to a
    /// child of the view that carries `.background(.bar)` — on the same view
    /// the material environment wins and the labels stay blank.
    func workspacePanelTextRendering() -> some View {
        environment(\.backgroundMaterial, nil)
    }
}
