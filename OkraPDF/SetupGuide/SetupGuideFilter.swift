import Foundation

/// Filter state for the setup guide's combination bar. Pure value type so the
/// bar, the list, and tests all share one matching implementation.
struct SetupGuideCombinationFilter: Equatable, Sendable {
    /// Empty means "all kinds".
    var deliveryKinds: Set<SetupGuideDeliveryKind> = []
    var onDeviceOnly = false
    var zeroSetupOnly = false
    var recommendedOnly = false
    var requiredCapabilities: Set<LocalParserCapability> = []

    var isActive: Bool {
        deliveryKinds.isEmpty == false
            || onDeviceOnly
            || zeroSetupOnly
            || recommendedOnly
            || requiredCapabilities.isEmpty == false
    }

    mutating func toggleDeliveryKind(_ kind: SetupGuideDeliveryKind) {
        if deliveryKinds.contains(kind) {
            deliveryKinds.remove(kind)
        } else {
            deliveryKinds.insert(kind)
        }
    }

    mutating func toggleCapability(_ capability: LocalParserCapability) {
        if requiredCapabilities.contains(capability) {
            requiredCapabilities.remove(capability)
        } else {
            requiredCapabilities.insert(capability)
        }
    }

    mutating func reset() {
        self = SetupGuideCombinationFilter()
    }

    func matches(_ combination: SetupGuideCombination) -> Bool {
        if deliveryKinds.isEmpty == false,
           deliveryKinds.contains(combination.deliveryKind) == false {
            return false
        }
        if onDeviceOnly {
            // System frameworks and okraPDF-managed models run fully on-device
            // with no separate runtime to install or keep running.
            let onDeviceKinds: Set<SetupGuideDeliveryKind> = [.system, .managedModel]
            guard onDeviceKinds.contains(combination.deliveryKind) else { return false }
        }
        if zeroSetupOnly, combination.requiresSetup {
            return false
        }
        if recommendedOnly, combination.isRecommended == false {
            return false
        }
        if requiredCapabilities.isEmpty == false,
           requiredCapabilities.isSubset(of: combination.capabilities) == false {
            return false
        }
        return true
    }
}
