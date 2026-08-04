import Darwin
import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

extension CLINotifyProcessIntegrationRegressionTests {
    func testSSHPTYAttachBridgeRPCTimeoutExitsRetryable() throws {
        try assertSSHPTYAttachBridgeRPCFailureExitCode(
            socketName: "sshptytimeout",
            error: [
                "code": "remote_pty_bridge_timeout",
                "message": "workspace.remote.pty_bridge timed out waiting for the remote daemon",
            ],
            expectedStatus: 255
        )
    }

    func testSSHPTYAttachBridgeRPCConnectionNotActiveExitsRetryable() throws {
        try assertSSHPTYAttachBridgeRPCFailureExitCode(
            socketName: "sshptynotactive",
            error: [
                "code": "remote_connection_inactive",
                "message": "remote connection is not active",
            ],
            expectedStatus: 255
        )
    }

    func testSSHPTYAttachBridgeRPCTransientFailureWithoutPendingWrapperRetryCleansUp() throws {
        // Final wrapper attempt (or direct invocation): no retry is queued,
        // so the CLI must send pty_attach_end and release the surface.
        try assertSSHPTYAttachBridgeRPCFailureExitCode(
            socketName: "sshptyexhausted",
            error: [
                "code": "remote_pty_bridge_timeout",
                "message": "workspace.remote.pty_bridge timed out waiting for the remote daemon",
            ],
            expectedStatus: 255,
            wrapperRetryPending: false
        )
    }

    func testSSHPTYAttachUnknownFlagStaysFatal() throws {
        let cliPath = try bundledCLIPath()
        let result = runProcess(
            executablePath: cliPath,
            arguments: [
                "ssh-pty-attach",
                "--bogus-flag",
            ],
            environment: sshPTYAttachTestEnvironment(socketPath: makeSocketPath("sshptybogus")),
            timeout: 5
        )

        XCTAssertFalse(result.timedOut, result.stderr)
        XCTAssertEqual(result.status, 1, result.stderr)
    }

    private func assertSSHPTYAttachBridgeRPCFailureExitCode(
        socketName: String,
        error: [String: Any],
        expectedStatus: Int32,
        wrapperRetryPending: Bool = true
    ) throws {
        let cliPath = try bundledCLIPath()
        let socketPath = makeSocketPath(socketName)
        let listenerFD = try bindUnixSocket(at: socketPath)
        let state = MockSocketServerState()
        let workspaceId = "22222222-2222-2222-2222-222222222222"
        let surfaceId = "33333333-3333-3333-3333-333333333333"
        let sessionId = "ssh-\(workspaceId)-\(surfaceId)"

        defer {
            Darwin.close(listenerFD)
            unlink(socketPath)
        }

        let socketHandled = startMockServer(
            listenerFD: listenerFD,
            state: state,
            fulfillWhen: { line in
                guard let payload = self.jsonObject(line) else { return false }
                return payload["method"] as? String == "workspace.remote.pty_bridge"
            }
        ) { line in
            guard let payload = self.jsonObject(line),
                  let id = payload["id"] as? String,
                  let method = payload["method"] as? String else {
                return self.malformedRequestResponse(raw: line)
            }
            let params = payload["params"] as? [String: Any] ?? [:]
            switch method {
            case "workspace.remote.pty_bridge":
                XCTAssertEqual(params["workspace_id"] as? String, workspaceId)
                XCTAssertEqual(params["session_id"] as? String, sessionId)
                XCTAssertEqual(params["attachment_id"] as? String, surfaceId)
                XCTAssertEqual(params["require_existing"] as? Bool, true)
                return self.v2Response(id: id, ok: false, error: error)
            case "workspace.remote.pty_detach":
                return self.v2Response(id: id, ok: true, result: ["detached": true])
            case "workspace.remote.pty_attach_end":
                return self.v2Response(id: id, ok: true, result: ["ended": true])
            default:
                return self.v2Response(
                    id: id,
                    ok: false,
                    error: ["code": "unexpected_method", "message": "Unexpected method \(method)"]
                )
            }
        }

        var environment = sshPTYAttachTestEnvironment(socketPath: socketPath)
        if wrapperRetryPending {
            environment["CMUX_SSH_PTY_ATTACH_WRAPPER_CAN_RETRY"] = "1"
        } else {
            environment.removeValue(forKey: "CMUX_SSH_PTY_ATTACH_WRAPPER_CAN_RETRY")
        }

        let result = runProcess(
            executablePath: cliPath,
            arguments: [
                "ssh-pty-attach",
                "--wait",
                "--require-existing",
                "--workspace", workspaceId,
                "--session-id", sessionId,
                "--attachment-id", surfaceId,
            ],
            environment: environment,
            timeout: 5
        )

        wait(for: [socketHandled], timeout: 5)
        XCTAssertFalse(result.timedOut, result.stderr)
        XCTAssertEqual(result.status, expectedStatus, result.stderr)

        let methods = state.snapshot().compactMap { self.jsonObject($0)?["method"] as? String }
        XCTAssertTrue(methods.contains("workspace.remote.pty_bridge"), "\(methods)")
        if wrapperRetryPending {
            // The wrapper re-runs the attach on this same surface; sending
            // pty_attach_end here would untrack it app-side and a successful
            // retry never re-tracks it.
            XCTAssertFalse(methods.contains("workspace.remote.pty_attach_end"), "\(methods)")
        } else {
            // No retry is queued: the CLI must release the surface.
            XCTAssertTrue(methods.contains("workspace.remote.pty_attach_end"), "\(methods)")
        }
    }

    func testRestoredPersistentAttachReauthenticatesAfterTransportLoss() throws {
        // Dead premise: this test stages a fake `ssh` on PATH, but the CLI's
        // interactive-auth path execs `/usr/bin/ssh` by absolute path on purpose
        // (`allowedSSHPaths` in CLI/cmux.swift's runInteractiveAuthSSH -- a
        // basename check would accept a planted /tmp/ssh, so the full path is
        // pinned against an argv that arrives over the control socket). The fake
        // is therefore never exec'd and the real ssh cannot resolve the fixture
        // host, so this can only ever fail. The pin itself is covered by
        // testInteractiveAuthRefusesPlantedAbsoluteSSHPath and its siblings.
        // Re-enable if an injectable transport seam is ever added; do not fix by
        // relaxing the pin.
        throw XCTSkip(
            "stages a fake ssh on PATH; the CLI pins /usr/bin/ssh by absolute path "
            + "(runInteractiveAuthSSH allowedSSHPaths), so the fixture is unreachable"
        )

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-restored-ssh-reauth-\(UUID().uuidString)", isDirectory: true)
        let fakeCLI = root.appendingPathComponent("cmux")
        let fakeSSH = root.appendingPathComponent("ssh")
        let fakeSleep = root.appendingPathComponent("sleep")
        let authAttempts = root.appendingPathComponent("auth-attempts")
        let attachAttempts = root.appendingPathComponent("attach-attempts")
        let sleepAttempts = root.appendingPathComponent("sleep-attempts")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try writeSSHPTYReconnectTestShell(at: fakeCLI, lines: [
            "#!/bin/sh",
            "case \" $* \" in",
            "  *\" ssh-pty-attach \"*)",
            "    count=$(cat \"${CMUX_TEST_ATTACH_ATTEMPTS}\" 2>/dev/null || printf 0)",
            "    count=$((count + 1))",
            "    printf '%s' \"$count\" > \"${CMUX_TEST_ATTACH_ATTEMPTS}\"",
            "    case \"$count\" in 1) exit 255 ;; 2) exit 254 ;; *) exit 253 ;; esac",
            "    ;;",
            "  *) exit 0 ;;",
            "esac",
        ])
        try writeSSHPTYReconnectTestShell(at: fakeSSH, lines: [
            "#!/bin/sh",
            "count=$(cat \"${CMUX_TEST_AUTH_ATTEMPTS}\" 2>/dev/null || printf 0)",
            "count=$((count + 1))",
            "printf '%s' \"$count\" > \"${CMUX_TEST_AUTH_ATTEMPTS}\"",
            "if [ \"$count\" -eq 2 ]; then exit 255; fi",
            "exit 0",
        ])
        try writeSSHPTYReconnectTestShell(at: fakeSleep, lines: [
            "#!/bin/sh",
            "count=$(cat \"${CMUX_TEST_SLEEP_ATTEMPTS}\" 2>/dev/null || printf 0)",
            "printf '%s' $((count + 1)) > \"${CMUX_TEST_SLEEP_ATTEMPTS}\"",
        ])
        for executable in [fakeCLI, fakeSSH, fakeSleep] {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        var environment = sshPTYAttachTestEnvironment(socketPath: "/tmp/cmux-debug-test.sock")
        environment["PATH"] = "\(root.path):\(environment["PATH"] ?? "/usr/bin:/bin")"
        environment["CMUX_BUNDLED_CLI_PATH"] = fakeCLI.path
        environment["CMUX_WORKSPACE_ID"] = "11111111-1111-1111-1111-111111111111"
        environment["CMUX_SURFACE_ID"] = "22222222-2222-2222-2222-222222222222"
        environment["CMUX_TEST_AUTH_ATTEMPTS"] = authAttempts.path
        environment["CMUX_TEST_ATTACH_ATTEMPTS"] = attachAttempts.path
        environment["CMUX_TEST_SLEEP_ATTEMPTS"] = sleepAttempts.path
        environment["CMUX_SSH_RECONNECT_DELAY_SECONDS"] = "2"
        environment["CMUX_SSH_RECONNECT_MAX_DELAY_SECONDS"] = "2"

        let command = SSHPTYAttachStartupCommandBuilder.command(
            sessionID: "ssh-test-session",
            foregroundAuth: SSHPTYAttachStartupCommandBuilder.ForegroundAuth(
                destination: "user@example.test",
                port: 22,
                identityFile: nil,
                sshOptions: [],
                token: "foreground-auth-token"
            )
        )
        let result = runProcess(
            executablePath: "/bin/sh",
            arguments: ["-c", command],
            environment: environment,
            timeout: 5
        )

        XCTAssertFalse(result.timedOut, result.stderr)
        XCTAssertEqual(result.status, 253, result.stderr)
        XCTAssertEqual(try String(contentsOf: authAttempts, encoding: .utf8), "3")
        XCTAssertEqual(try String(contentsOf: attachAttempts, encoding: .utf8), "3")
        XCTAssertEqual(try String(contentsOf: sleepAttempts, encoding: .utf8), "3")
    }

    func testInitialPersistentAttachReauthenticatesAfterTransportLoss() throws {
        // Dead premise: this test stages a fake `ssh` on PATH, but the CLI's
        // interactive-auth path execs `/usr/bin/ssh` by absolute path on purpose
        // (`allowedSSHPaths` in CLI/cmux.swift's runInteractiveAuthSSH -- a
        // basename check would accept a planted /tmp/ssh, so the full path is
        // pinned against an argv that arrives over the control socket). The fake
        // is therefore never exec'd and the real ssh cannot resolve the fixture
        // host, so this can only ever fail. The pin itself is covered by
        // testInteractiveAuthRefusesPlantedAbsoluteSSHPath and its siblings.
        // Re-enable if an injectable transport seam is ever added; do not fix by
        // relaxing the pin.
        throw XCTSkip(
            "stages a fake ssh on PATH; the CLI pins /usr/bin/ssh by absolute path "
            + "(runInteractiveAuthSSH allowedSSHPaths), so the fixture is unreachable"
        )

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-initial-ssh-reauth-\(UUID().uuidString)", isDirectory: true)
        let fakeStartup = root.appendingPathComponent("startup")
        let fakeAuth = root.appendingPathComponent("ssh")
        let fakeAttach = root.appendingPathComponent("cmux-test-attach")
        let fakeSleep = root.appendingPathComponent("sleep")
        let authAttempts = root.appendingPathComponent("auth-attempts")
        let attachAttempts = root.appendingPathComponent("attach-attempts")
        let sleepAttempts = root.appendingPathComponent("sleep-attempts")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try writeSSHPTYReconnectTestShell(at: fakeAuth, lines: [
            "#!/bin/sh",
            "case \" $* \" in",
            "  *\" -T example.test true \"*) ;;",
            "  *) exit 0 ;;",
            "esac",
            "count=$(cat \"${CMUX_TEST_AUTH_ATTEMPTS}\" 2>/dev/null || printf 0)",
            "count=$((count + 1))",
            "printf '%s' \"$count\" > \"${CMUX_TEST_AUTH_ATTEMPTS}\"",
            "if [ \"$count\" -eq 2 ]; then exit 255; fi",
            "exit 0",
        ])
        try writeSSHPTYReconnectTestShell(at: fakeAttach, lines: [
            "#!/bin/sh",
            "case \" $* \" in",
            "  *\" ssh-pty-attach \"*)",
            "    count=$(cat \"${CMUX_TEST_ATTACH_ATTEMPTS}\" 2>/dev/null || printf 0)",
            "    count=$((count + 1))",
            "    printf '%s' \"$count\" > \"${CMUX_TEST_ATTACH_ATTEMPTS}\"",
            "    case \"$count\" in 1) exit 255 ;; 2) exit 254 ;; *) exit 253 ;; esac",
            "    ;;",
            "  *) exit 0 ;;",
            "esac",
        ])
        try writeSSHPTYReconnectTestShell(at: fakeSleep, lines: [
            "#!/bin/sh",
            "count=$(cat \"${CMUX_TEST_SLEEP_ATTEMPTS}\" 2>/dev/null || printf 0)",
            "printf '%s' $((count + 1)) > \"${CMUX_TEST_SLEEP_ATTEMPTS}\"",
        ])

        let generatedScript = try persistentSSHInitialStartupScriptForReconnectTest()
        let bundledCLI = try bundledCLIPath()
        let rewrittenScript = generatedScript.replacingOccurrences(of: bundledCLI, with: fakeAttach.path)
        XCTAssertNotEqual(rewrittenScript, generatedScript, "Expected generated wrapper to reference the bundled CLI")
        try writeSSHPTYReconnectTestShell(at: fakeStartup, contents: rewrittenScript)
        for executable in [fakeStartup, fakeAuth, fakeAttach, fakeSleep] {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        var environment = sshPTYAttachTestEnvironment(socketPath: "/tmp/cmux-debug-test.sock")
        environment["PATH"] = "\(root.path):\(environment["PATH"] ?? "/usr/bin:/bin")"
        environment["CMUX_BUNDLED_CLI_PATH"] = fakeAttach.path
        environment["CMUX_WORKSPACE_ID"] = "11111111-1111-1111-1111-111111111111"
        environment["CMUX_SURFACE_ID"] = "22222222-2222-2222-2222-222222222222"
        environment["CMUX_TEST_AUTH_ATTEMPTS"] = authAttempts.path
        environment["CMUX_TEST_ATTACH_ATTEMPTS"] = attachAttempts.path
        environment["CMUX_TEST_SLEEP_ATTEMPTS"] = sleepAttempts.path
        environment["CMUX_SSH_RECONNECT_DELAY_SECONDS"] = "2"
        environment["CMUX_SSH_RECONNECT_MAX_DELAY_SECONDS"] = "2"

        let result = runProcess(
            executablePath: fakeStartup.path,
            arguments: [],
            environment: environment,
            timeout: 5
        )

        XCTAssertFalse(result.timedOut, result.stderr)
        XCTAssertEqual(result.status, 253, result.stderr)
        XCTAssertEqual(try String(contentsOf: authAttempts, encoding: .utf8), "3")
        XCTAssertEqual(try String(contentsOf: attachAttempts, encoding: .utf8), "3")
        XCTAssertEqual(try String(contentsOf: sleepAttempts, encoding: .utf8), "3")
    }

    func testSSHPTYAttachSilentBridgeTimesOutRetryable() throws {
        let cliPath = try bundledCLIPath()
        let socketPath = makeSocketPath("sshptysilent")
        let listenerFD = try bindUnixSocket(at: socketPath)
        let bridge = try bindLoopbackTCP()
        let state = MockSocketServerState()
        let workspaceId = "22222222-2222-2222-2222-222222222222"
        let surfaceId = "33333333-3333-3333-3333-333333333333"
        let sessionId = "ssh-\(workspaceId)-\(surfaceId)"
        let token = "bridge-token"

        defer {
            Darwin.close(listenerFD)
            Darwin.close(bridge.fd)
            unlink(socketPath)
        }

        let socketHandled = startMockServer(
            listenerFD: listenerFD,
            state: state,
            fulfillWhen: { line in
                guard let payload = self.jsonObject(line) else { return false }
                return payload["method"] as? String == "workspace.remote.pty_bridge"
            }
        ) { line in
            guard let payload = self.jsonObject(line),
                  let id = payload["id"] as? String,
                  let method = payload["method"] as? String else {
                return self.malformedRequestResponse(raw: line)
            }
            switch method {
            case "workspace.remote.pty_bridge":
                return self.v2Response(
                    id: id,
                    ok: true,
                    result: [
                        "host": "127.0.0.1",
                        "port": bridge.port,
                        "token": token,
                        "session_id": sessionId,
                        "attachment_id": surfaceId,
                    ]
                )
            case "workspace.remote.pty_detach":
                return self.v2Response(id: id, ok: true, result: ["detached": true])
            case "workspace.remote.pty_attach_end":
                return self.v2Response(id: id, ok: true, result: ["ended": true])
            default:
                return self.v2Response(
                    id: id,
                    ok: false,
                    error: ["code": "unexpected_method", "message": "Unexpected method \(method)"]
                )
            }
        }
        let bridgeHandled = startSilentBridgeServer(listenerFD: bridge.fd)

        var environment = sshPTYAttachTestEnvironment(socketPath: socketPath)
        environment["CMUX_SSH_PTY_BRIDGE_READY_TIMEOUT_SECONDS"] = "1"
        environment["CMUX_SSH_PTY_ATTACH_WRAPPER_CAN_RETRY"] = "1"

        let result = runProcess(
            executablePath: cliPath,
            arguments: [
                "ssh-pty-attach",
                "--require-existing",
                "--workspace", workspaceId,
                "--session-id", sessionId,
                "--attachment-id", surfaceId,
            ],
            environment: environment,
            timeout: 10
        )

        wait(for: [socketHandled, bridgeHandled], timeout: 10)
        XCTAssertFalse(result.timedOut, result.stderr)
        XCTAssertEqual(result.status, 255, result.stderr)
        XCTAssertTrue(
            result.stderr.contains("timed out waiting for bridge status"),
            result.stderr
        )
        let methods = state.snapshot().compactMap { self.jsonObject($0)?["method"] as? String }
        XCTAssertTrue(methods.contains("workspace.remote.pty_bridge"), "\(methods)")
        // Wrapper-retryable failures re-run the attach on this same surface;
        // sending pty_attach_end here would untrack it app-side and a
        // successful retry never re-tracks it.
        XCTAssertFalse(methods.contains("workspace.remote.pty_attach_end"), "\(methods)")
    }

    /// Accepts one bridge connection, drains the client handshake, and never
    /// writes a status line, so the CLI's bounded ready wait must fire.
    private func startSilentBridgeServer(listenerFD: Int32) -> XCTestExpectation {
        let handled = expectation(description: "silent pty bridge server handled")
        DispatchQueue.global(qos: .userInitiated).async {
            defer { handled.fulfill() }

            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.accept(listenerFD, sockaddrPtr, &clientAddrLen)
                }
            }
            guard clientFD >= 0 else { return }
            defer { Darwin.close(clientFD) }

            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = Darwin.read(clientFD, &buffer, buffer.count)
                if count > 0 { continue }
                if count < 0 && errno == EINTR { continue }
                return
            }
        }
        return handled
    }

    private func sshPTYAttachTestEnvironment(socketPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_SOCKET_PATH"] = socketPath
        environment["CMUX_CLI_SENTRY_DISABLED"] = "1"
        return environment
    }

    private func writeSSHPTYReconnectTestShell(at url: URL, lines: [String]) throws {
        try writeSSHPTYReconnectTestShell(at: url, contents: lines.joined(separator: "\n") + "\n")
    }

    private func writeSSHPTYReconnectTestShell(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Interactive-auth ssh path pin

/// `runInteractiveAuthSSH` (CLI/cmux.swift, the `allowedSSHPaths` guard) refuses
/// to exec anything but `/usr/bin/ssh`. The argv it runs arrives over the control
/// socket, so a compromised or spoofed peer that could return an arbitrary path
/// would otherwise get arbitrary code exec'd in the user's terminal, with the
/// terminal foreground process group handed to it.
///
/// Nothing exercised that guard before. These cases do, from both sides.
extension CLINotifyProcessIntegrationRegressionTests {
    private static let nonStandardSSHPathRefusal =
        "refusing to run a non-standard ssh path"

    /// Drives `zerocmux ssh-tmux --new-window` against a mock control socket that
    /// answers with `auth_required` plus the supplied argv, with stdin on a pty so
    /// the interactive-auth path's `isatty` precondition is satisfied.
    private func runInteractiveAuthWithSSHArgv(
        _ sshArgv: [String],
        socketLabel: String
    ) throws -> (status: Int32, output: String) {
        let cliPath = try bundledCLIPath()
        let socketPath = makeSocketPath(socketLabel)
        let listenerFD = try bindUnixSocket(at: socketPath)
        let state = MockSocketServerState()
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1

        defer {
            if masterFD >= 0 { Darwin.close(masterFD) }
            if slaveFD >= 0 { Darwin.close(slaveFD) }
            Darwin.close(listenerFD)
            unlink(socketPath)
        }

        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw NSError(domain: "cmux.tests", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "openpty failed: \(String(cString: strerror(errno)))",
            ])
        }

        // First mirror request demands interactive auth; a second one (only
        // reached when the guard accepts the path) completes the flow so the CLI
        // exits instead of looping.
        let authRequired = NSLock()
        var servedAuthRequired = false
        let serverHandled = startMockServer(listenerFD: listenerFD, state: state) { line in
            guard let payload = self.jsonObject(line),
                  let id = payload["id"] as? String,
                  let method = payload["method"] as? String else {
                return self.malformedRequestResponse(raw: line)
            }
            guard method == "remote.tmux.window" else {
                return self.v2Response(id: id, ok: true, result: [:])
            }
            authRequired.lock()
            let alreadyServed = servedAuthRequired
            servedAuthRequired = true
            authRequired.unlock()
            if alreadyServed {
                return self.v2Response(
                    id: id,
                    ok: true,
                    result: ["mirrored": true, "window_id": "window:1", "workspace_ids": []]
                )
            }
            return self.v2Response(
                id: id,
                ok: true,
                result: ["auth_required": true, "ssh_argv": sshArgv]
            )
        }

        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_SOCKET_PATH"] = socketPath
        environment["CMUX_CLI_SENTRY_DISABLED"] = "1"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["ssh-tmux", "--new-window", "user@example.invalid"]
        process.environment = environment
        let outputPipe = Pipe()
        process.standardInput = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()

        let collected = NSMutableData()
        let collectedLock = NSLock()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            collectedLock.lock()
            collected.append(data)
            collectedLock.unlock()
            drained.signal()
        }

        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            XCTFail("`zerocmux ssh-tmux` did not exit within 20s")
        }
        process.waitUntilExit()
        _ = drained.wait(timeout: .now() + 5)

        // The CLI always dials the control socket here (unlike the removed
        // hosted verbs), so this expectation is genuinely fulfilled.
        wait(for: [serverHandled], timeout: 10)

        collectedLock.lock()
        let output = String(data: collected as Data, encoding: .utf8) ?? ""
        collectedLock.unlock()
        return (process.terminationStatus, output)
    }

    func testInteractiveAuthRefusesPlantedAbsoluteSSHPath() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-ssh-path-pin-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        // A planted "ssh" that records the fact it ran. The pin must mean this
        // file is never executed, which is a stronger claim than the error text.
        let planted = root.appendingPathComponent("ssh")
        let executedMarker = root.appendingPathComponent("planted-ran.txt")
        try """
        #!/bin/sh
        printf 'ran\\n' > "\(executedMarker.path)"
        exit 0
        """.write(to: planted, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: planted.path)

        let result = try runInteractiveAuthWithSSHArgv(
            [planted.path, "user@example.invalid"],
            socketLabel: "ssh-pin-planted"
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains(Self.nonStandardSSHPathRefusal),
            "expected the pinned-path refusal, got \(result.output)"
        )
        XCTAssertFalse(
            fileManager.fileExists(atPath: executedMarker.path),
            "the planted ssh must never be executed"
        )
    }

    func testInteractiveAuthRefusesRelativeSSHName() throws {
        let result = try runInteractiveAuthWithSSHArgv(
            ["ssh", "user@example.invalid"],
            socketLabel: "ssh-pin-relative"
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains(Self.nonStandardSSHPathRefusal),
            "a bare `ssh` resolves through PATH and must be refused, got \(result.output)"
        )
    }

    /// The other half of the control: the pinned path is admitted. `-V` makes the
    /// accepted exec hermetic (OpenSSH prints its version to stderr and exits 0)
    /// while still proving the guard handed off to the real binary.
    func testInteractiveAuthAcceptsPinnedSystemSSHPath() throws {
        let result = try runInteractiveAuthWithSSHArgv(
            ["/usr/bin/ssh", "-V"],
            socketLabel: "ssh-pin-allowed"
        )

        XCTAssertFalse(
            result.output.contains(Self.nonStandardSSHPathRefusal),
            "/usr/bin/ssh must pass the pin, got \(result.output)"
        )
        XCTAssertTrue(
            result.output.contains("OpenSSH"),
            "expected the pinned ssh binary to actually run, got \(result.output)"
        )
    }
}

