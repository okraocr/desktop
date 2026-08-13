import Foundation

protocol ChandraOCRModelInstalling: Sendable {
    func install(
        runtime: ChandraOCRRuntime,
        scriptURL: URL,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws
}
