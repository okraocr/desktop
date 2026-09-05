import Foundation

@objc protocol ProviderRuntimeXPCProtocol {
    // The service accepts catalog IDs only, never commands, paths, or URLs.
    func install(providerID: String, withReply reply: @escaping (Int32, String) -> Void)
    func cancel()
}

enum ProviderRuntimeServiceConfiguration {
    static let identifier = "com.okrapdf.desktop.provider-installer"
    static let scripts = [
        "unlimited-ocr": "install-unlimited-ocr.sh",
        "dots-ocr": "install-dots-ocr.sh",
        "chandra-ocr-2": "install-chandra-ocr.sh",
        "presidio": "install-presidio.sh",
    ]
}
