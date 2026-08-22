import Foundation

extension LocalProviderDescriptor {
    var downloadSizeBytes: Int64? {
        parserDefinition?.modelDelivery.pinnedPackage?.totalBytes
    }

    var installLocation: String? {
        switch id {
        case .appleVision:
            nil
        case .chandraOCR2:
            LocalProviderPaths.chandraOCRRoot.path(percentEncoded: false)
        case .dotsOCR:
            LocalProviderPaths.dotsOCRRoot.path(percentEncoded: false)
        case .hybridAuto:
            nil
        case .unlimitedOCR:
            LocalProviderPaths.unlimitedOCRRoot.path(percentEncoded: false)
        case .ollama:
            nil
        }
    }
}
