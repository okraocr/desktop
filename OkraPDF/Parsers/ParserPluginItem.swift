import Foundation

/// One row in the Parsers panel: a local parser, whether it can run on this Mac
/// right now, and the doctor badge that explains why you would pick it.
///
/// The assistant shell already calls Extract, Redact, and Runs "plugins", so
/// parsers keep their own name in code even though they mount the same way.
///
/// Built from plain values rather than from the coordinator so the mapping can
/// be tested without standing up a provider stack or a view.
struct ParserPluginItem: Identifiable, Equatable {
    enum Readiness: Equatable {
        case ready
        case simulated
        case needsSetup
        case unavailable
    }

    let id: LocalProviderID
    let name: String
    let summary: String
    /// The availability line, e.g. "Ready offline" or what setup is missing.
    let statusMessage: String
    let readiness: Readiness
    let badge: LocalParserBadge?
    let isSelected: Bool

    /// Can this plugin parse a document as it stands?
    var isRunnable: Bool {
        readiness == .ready || readiness == .simulated
    }

    /// Setup is something the reader can act on; unavailable is not.
    var canInstall: Bool {
        readiness == .needsSetup
    }

    var systemImage: String {
        switch readiness {
        case .ready:
            return "checkmark.circle.fill"
        case .simulated:
            return "exclamationmark.triangle.fill"
        case .needsSetup:
            return "arrow.down.circle"
        case .unavailable:
            return "slash.circle"
        }
    }

    var accessibilityDescription: String {
        [name, badge?.rawValue, statusMessage]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    static func readiness(for availability: LocalProviderAvailability?) -> Readiness {
        switch availability {
        case .ready:
            return .ready
        case .simulated:
            return .simulated
        case .setupRequired:
            return .needsSetup
        case .unavailable, .none:
            return .unavailable
        }
    }

    /// Descriptor order is preserved: it is the order the app offers parsers in,
    /// and re-sorting by readiness would move rows under the pointer as models
    /// finish installing.
    static func items(
        descriptors: [LocalProviderDescriptor],
        availability: [LocalProviderID: LocalProviderAvailability],
        badges: [LocalProviderID: LocalParserBadge],
        selected: LocalProviderID
    ) -> [ParserPluginItem] {
        descriptors.map { descriptor in
            let providerAvailability = availability[descriptor.id]
            return ParserPluginItem(
                id: descriptor.id,
                name: descriptor.name,
                summary: descriptor.summary,
                statusMessage: providerAvailability?.message ?? "Unavailable",
                readiness: readiness(for: providerAvailability),
                badge: badges[descriptor.id],
                isSelected: descriptor.id == selected
            )
        }
    }
}
