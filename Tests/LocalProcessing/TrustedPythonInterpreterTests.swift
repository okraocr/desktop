import Foundation
import Testing
@testable import Okra

struct TrustedPythonInterpreterTests {
    @Test(
        "Interpreter policy accepts only declared candidates inside trusted roots",
        .bug("https://github.com/okrapdf/desktop/issues/99")
    )
    func acceptsDeclaredContainedCandidate() throws {
        let workspace = try TestWorkspace(prefix: "okra-trusted-python")
        let trustedRoot = workspace.root.appendingPathComponent("trusted", isDirectory: true)
        let pythonURL = trustedRoot.appendingPathComponent("python3")
        try FileManager.default.createDirectory(at: trustedRoot, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: pythonURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pythonURL.path
        )
        let policy = TrustedPythonInterpreterPolicy(
            candidates: [pythonURL],
            trustedRoots: [trustedRoot],
            trustedSystemExecutables: []
        )

        #expect(policy.isTrustedExecutable(pythonURL))
        #expect(
            policy.isTrustedExecutable(
                workspace.root.appendingPathComponent("undeclared-python")
            ) == false
        )
    }

    @Test(
        "Interpreter policy rejects a declared symlink that escapes its trusted root",
        .bug("https://github.com/okrapdf/desktop/issues/99")
    )
    func rejectsSymlinkEscape() throws {
        let workspace = try TestWorkspace(prefix: "okra-python-symlink")
        let trustedRoot = workspace.root.appendingPathComponent("trusted", isDirectory: true)
        let outsideRoot = workspace.root.appendingPathComponent("outside", isDirectory: true)
        let outsidePython = outsideRoot.appendingPathComponent("python3")
        let candidate = trustedRoot.appendingPathComponent("python3")
        try FileManager.default.createDirectory(at: trustedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: outsidePython)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: outsidePython.path
        )
        try FileManager.default.createSymbolicLink(
            at: candidate,
            withDestinationURL: outsidePython
        )
        let policy = TrustedPythonInterpreterPolicy(
            candidates: [candidate],
            trustedRoots: [trustedRoot],
            trustedSystemExecutables: []
        )

        #expect(policy.isTrustedExecutable(candidate) == false)
    }
}
