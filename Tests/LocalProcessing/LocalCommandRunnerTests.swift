import Darwin
import Foundation
import Testing
@testable import Okra

struct LocalCommandRunnerTests {
    @Test(
        "Provider children receive only the minimal approved environment",
        .bug("https://github.com/okrapdf/desktop/issues/99")
    )
    func childEnvironmentIsAllowlisted() throws {
        let environment = try LocalProcessEnvironment.make(
            parent: [
                "API_TOKEN": "must-not-leak",
                "DYLD_INSERT_LIBRARIES": "/tmp/injected.dylib",
                "LANG": "en_US.UTF-8",
                "PATH": "/tmp/attacker-bin",
                "PYTHONPATH": "/tmp/attacker-python",
            ],
            additions: [
                "HF_HUB_OFFLINE": "1",
                "OLLAMA_HOST": "http://127.0.0.1:11434",
            ]
        )

        #expect(environment["PATH"] == LocalProcessEnvironment.fixedPath)
        #expect(environment["LANG"] == "en_US.UTF-8")
        #expect(environment["HF_HUB_OFFLINE"] == "1")
        #expect(environment["OLLAMA_HOST"] == "http://127.0.0.1:11434")
        #expect(environment["API_TOKEN"] == nil)
        #expect(environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(environment["PYTHONPATH"] == nil)
    }

    @Test(
        "Command output is transient diagnostic detail",
        .bug("https://github.com/okrapdf/desktop/issues/99")
    )
    func commandOutputIsTransientDiagnosticDetail() throws {
        let secret = "provider-stderr-secret"
        do {
            _ = try LocalCommandRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-c", "print -u2 -- \(secret); exit 23"]
            )
            Issue.record("A failing provider command unexpectedly succeeded")
        } catch let error as LocalProcessingError {
            #expect(error.localizedDescription.contains(secret) == false)
            #expect(error.diagnosticDescription.contains(secret))
        }
    }

    @Test("Canceling an async provider command terminates its process", .timeLimit(.minutes(1)))
    func cancellationTerminatesProcess() async throws {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            try await LocalCommandRunner.runAsync(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"]
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Canceled provider command unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: the runner reports cancellation after the child exits.
        }

        #expect(startedAt.duration(to: clock.now) < .seconds(3))
    }

    @Test("Canceling a provider shell terminates its descendant process", .timeLimit(.minutes(1)))
    func cancellationTerminatesDescendantProcess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-command-group-\(UUID().uuidString)", isDirectory: true)
        let childPIDURL = root.appendingPathComponent("child.pid")
        let heartbeatURL = root.appendingPathComponent("child-heartbeat.log")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let script = """
        (
          trap '' TERM
          while true; do
            print -r -- tick >> "$2"
            sleep 0.05
          done
        ) &
        child_pid=$!
        print -r -- "$child_pid" > "$1"
        wait "$child_pid"
        """
        let task = Task {
            try await LocalCommandRunner.runAsync(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [
                    "-c",
                    script,
                    "okra-command-group",
                    childPIDURL.path,
                    heartbeatURL.path,
                ]
            )
        }

        let childPID = try await waitForChildPID(at: childPIDURL)
        defer {
            task.cancel()
            let processGroupID = Darwin.getpgid(childPID)
            if processGroupID > 0, processGroupID != Darwin.getpgrp() {
                Darwin.kill(-processGroupID, SIGKILL)
            } else {
                Darwin.kill(childPID, SIGKILL)
            }
        }
        #expect(Darwin.kill(childPID, 0) == 0)
        try await waitForHeartbeat(at: heartbeatURL)

        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Canceled provider shell unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: the runner reports cancellation after the group leader exits.
        }

        try await Task.sleep(for: .milliseconds(1_400))
        let heartbeatSizeAfterForceKill = try #require(fileSize(at: heartbeatURL))
        #expect(heartbeatSizeAfterForceKill > 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fileSize(at: heartbeatURL) == heartbeatSizeAfterForceKill)
    }

    private func waitForChildPID(at url: URL) async throws -> pid_t {
        for _ in 0..<100 {
            if let contents = try? String(contentsOf: url, encoding: .utf8),
               let processID = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return processID
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw LocalCommandRunnerTestError.childDidNotStart
    }

    private func waitForHeartbeat(at url: URL) async throws {
        for _ in 0..<100 {
            if let size = fileSize(at: url), size > 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw LocalCommandRunnerTestError.childDidNotProduceHeartbeat
    }

    private func fileSize(at url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}

private enum LocalCommandRunnerTestError: Error {
    case childDidNotStart
    case childDidNotProduceHeartbeat
}
