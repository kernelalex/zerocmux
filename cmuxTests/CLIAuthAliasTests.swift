import XCTest
import Darwin

/// zerocmux removed the hosted web backend, so there is no sign-in popup behind
/// `login` / `logout` / `auth`. Upstream's aliases forwarded to
/// `auth.begin_sign_in` / `auth.sign_out` over the socket; this fork answers
/// them locally instead.
///
/// These tests pin that replacement contract rather than the removed one. The
/// interesting property is not just "it errors" — it is that the verbs stay
/// *recognized*, so users get an explanation instead of "Unknown command", and
/// that they resolve without opening a socket conversation at all, which is
/// what keeps the zero-telemetry promise verifiable.
extension CLINotifyProcessIntegrationRegressionTests {
    func testTopLevelLoginReportsHostedAuthRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(["login"], socketLabel: "auth-login")
    }

    func testTopLevelLogoutReportsHostedAuthRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(["logout"], socketLabel: "auth-logout")
    }

    func testAuthNamespaceReportsHostedAuthRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(["auth", "status"], socketLabel: "auth-status")
    }

    /// Scripts that ask for `--json` must get a machine-readable refusal rather
    /// than a bare non-zero exit, so automation can tell "removed" apart from
    /// "the app is not running".
    func testRemovedHostedVerbsEmitMachineReadableUnavailability() throws {
        let (result, socketTraffic) = try runRemovedHostedVerb(
            ["logout", "--json"],
            socketLabel: "auth-logout-json"
        )

        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertEqual(socketTraffic, [], "saw \(socketTraffic)")

        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
            "expected a JSON document on stdout, got \(result.stdout)"
        )
        XCTAssertEqual(document["available"] as? Bool, false)
        XCTAssertEqual(document["reason"] as? String, Self.hostedServicesUnavailableMessage)
    }
}
