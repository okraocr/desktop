import Darwin
import Foundation

public enum LaunchServicesCommand {
    /// Dispatches an `open` request without allowing the helper process to
    /// block the caller indefinitely. LaunchServices may keep `/usr/bin/open`
    /// alive during a quarantined first launch even after the app process has
    /// started, so timeout is treated as a successfully dispatched request.
    public static func dispatch(
        arguments: [String],
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/open"),
        waitLimit: TimeInterval = 5
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()

        let deadline = Date().addingTimeInterval(max(0, waitLimit))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            return
        }

        guard process.terminationStatus == 0 else {
            throw LaunchServicesCommandError.failed(process.terminationStatus)
        }
    }
}

public enum LaunchServicesCommandError: LocalizedError {
    case failed(Int32)

    public var errorDescription: String? {
        switch self {
        case .failed(let status):
            return "LaunchServices helper exited with status \(status)."
        }
    }
}
