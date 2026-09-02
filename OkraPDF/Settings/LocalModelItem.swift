import Foundation

enum LocalModelCollection: String, CaseIterable {
    case installed = "Installed & built in"
    case available = "Available to download"
    case unavailable = "Unavailable on this Mac"
}

/// A settings-facing model row built from the provider catalog and current
/// host state. It deliberately contains no view or coordinator behavior so
/// collection membership and accessibility copy stay testable.
struct LocalModelItem: Identifiable, Equatable {
    enum Readiness: Equatable {
        case ready
        case simulated
        case needsSetup
        case unavailable
    }

    let id: LocalProviderID
    let name: String
    let summary: String
    let statusMessage: String
    let readiness: Readiness
    let badge: LocalParserBadge?
    let isSelected: Bool
    let downloadSizeBytes: Int64?

    var isRunnable: Bool {
        readiness == .ready || readiness == .simulated
    }

    var canInstall: Bool { readiness == .needsSetup }

    var collection: LocalModelCollection {
        switch readiness {
        case .ready, .simulated:
            return .installed
        case .needsSetup:
            return .available
        case .unavailable:
            return .unavailable
        }
    }

    var systemImage: String {
        switch readiness {
        case .ready: return "checkmark.circle.fill"
        case .simulated: return "exclamationmark.triangle.fill"
        case .needsSetup: return "arrow.down.circle"
        case .unavailable: return "slash.circle"
        }
    }

    var accessibilityDescription: String {
        [name, badge?.rawValue, isSelected ? "Active" : nil, statusMessage]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    static func readiness(for availability: LocalProviderAvailability?) -> Readiness {
        switch availability {
        case .ready: return .ready
        case .simulated: return .simulated
        case .setupRequired: return .needsSetup
        case .unavailable, .none: return .unavailable
        }
    }

    static func items(
        descriptors: [LocalProviderDescriptor],
        availability: [LocalProviderID: LocalProviderAvailability],
        badges: [LocalProviderID: LocalParserBadge],
        selected: LocalProviderID
    ) -> [LocalModelItem] {
        descriptors.map { descriptor in
            let providerAvailability = availability[descriptor.id]
            return LocalModelItem(
                id: descriptor.id,
                name: descriptor.name,
                summary: descriptor.summary,
                statusMessage: providerAvailability?.message ?? "Unavailable",
                readiness: readiness(for: providerAvailability),
                badge: badges[descriptor.id],
                isSelected: descriptor.id == selected,
                downloadSizeBytes: descriptor.downloadSizeBytes
            )
        }
    }
}
