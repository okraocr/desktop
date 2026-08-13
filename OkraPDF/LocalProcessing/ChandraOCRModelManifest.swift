import Foundation

enum ChandraOCRModelManifest {
    static let repository = "mlx-community/chandra-ocr-2-oQ8"
    static let revision = "eafcb4c79468ff6cf8b76ecc3aedbffe0dd82282"

    static let artifacts = [
        LocalModelArtifact(
            path: "chat_template.jinja",
            size: 7_622,
            sha256: "0d158f349ca965f7eea9db0eb45cd177b85bb0e4ae05dcdd0f060da8f7d41812"
        ),
        LocalModelArtifact(
            path: "config.json",
            size: 2_966,
            sha256: "c4794a2b9157bfbba454de15a3848f801bc9e1f9d8fd493856b4e550ace4ad6b"
        ),
        LocalModelArtifact(
            path: "generation_config.json",
            size: 115,
            sha256: "0c35bb39fbaed1ac0656baabc4f4e9bda20214e12336d0e4e8755aac1f487c2e"
        ),
        LocalModelArtifact(
            path: "model-00001-of-00002.safetensors",
            size: 5_000_801_612,
            sha256: "970ad5f1f22a2ce95a4ce69fc291e73d4a9b11c24cc8bcffe6a76ad49a4ffce9"
        ),
        LocalModelArtifact(
            path: "model-00002-of-00002.safetensors",
            size: 135_892_572,
            sha256: "af58a25ef629a400f228f52ac50e14e588585644fab26ee9057dc7ca8db3bf7e"
        ),
        LocalModelArtifact(
            path: "model.safetensors.index.json",
            size: 115_363,
            sha256: "7621a7f442eec1425de0ae61a5bdb983c3cf364db514f4817844477a387eb499"
        ),
        LocalModelArtifact(
            path: "preprocessor_config.json",
            size: 482,
            sha256: "957eb01d1ea45341a92d543daec95857a7cbeff5803834bc0603b27ba7b41b3f"
        ),
        LocalModelArtifact(
            path: "tokenizer.json",
            size: 19_989_343,
            sha256: "87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4"
        ),
        LocalModelArtifact(
            path: "tokenizer_config.json",
            size: 16_710,
            sha256: "316230d6a809701f4db5ea8f8fc862bc3a6f3229c937c174e674ff3ca0a64ac8"
        ),
    ]

    static let package = LocalModelPackageManifest(
        displayName: "Chandra OCR 2",
        upstreamRepository: "datalab-to/chandra-ocr-2",
        repository: repository,
        revision: revision,
        format: .mlxSafetensors,
        quantization: LocalModelQuantization(bits: 8, scheme: "affine-int8-group-64"),
        parameterCount: nil,
        licenseSPDXIdentifier: "LicenseRef-OpenRAIL",
        licenseURL: URL(
            string: "https://huggingface.co/datalab-to/chandra-ocr-2/blob/af93b47dba1b47b6640c86ccf487ed2260ab9a09/LICENSE"
        ),
        licenseRevision: "af93b47dba1b47b6640c86ccf487ed2260ab9a09",
        licenseNotice: "Use is subject to the upstream OpenRAIL license, including its use restrictions.",
        artifacts: artifacts
    )

    static let totalBytes = package.totalBytes

    static func downloadURL(for artifact: LocalModelArtifact) -> URL? {
        package.downloadURL(for: artifact)
    }
}
