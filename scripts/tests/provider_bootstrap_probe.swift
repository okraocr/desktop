import Foundation

// Run as a signed app: an ordinary `swift test` process does not inherit App Sandbox.
let fileManager = FileManager.default
let container = fileManager.homeDirectoryForCurrentUser
guard container.path.contains("/Library/Containers/com.okrapdf.bootstrap-test.") else {
    fatalError("Bootstrap regression must run inside its own app sandbox")
}
let workspace = container.appendingPathComponent("Library/Application Support/Bootstrap Test")
try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: workspace) }

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = try LocalProcessEnvironment.make()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        exit(process.terminationStatus)
    }
}

let python = CommandLine.arguments[1]
let venv = workspace.appendingPathComponent("venv")
let installedPython = venv.appendingPathComponent("bin/python").path
// Both a clean install and Retry Setup must be able to bootstrap pip. Keep the
// real sandbox container path, including Application Support's space.
for _ in 0..<2 {
    try run(python, ["-m", "venv", "--clear", venv.path])
    try run(installedPython, ["-m", "pip", "--version"])
    try run(installedPython, ["-c", """
        import mimetypes
        assert mimetypes.guess_type('document.pdf')[0] == 'application/pdf'
        with open('/etc/apache2/mime.types') as registry:
            assert registry.read(1)
        """])
}
print("Sandboxed Python bootstrap and retry passed")
