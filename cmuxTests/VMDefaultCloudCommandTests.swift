import XCTest
import Darwin

/// Upstream's Cloud VM control plane (`vm new`, provider selection, freestyle
/// SSH attach, credential prompts, retry countdowns) is not part of zerocmux:
/// the hosted backend was removed, and `CMUXCLI` answers `vm` / `cloud` and the
/// VM attach entrypoints with `hostedServicesUnavailable` before any socket
/// request is made.
///
/// The upstream tests that used to live here drove a mock socket through
/// `vm.create` / `vm.list` conversations that this fork can never produce, so
/// they asserted a contract with no implementation behind it. What remains
/// worth pinning is the fork's own contract: those verbs stay recognized,
/// explain themselves, and never talk to the socket. That last property is the
/// zero-telemetry guarantee, and it is the reason these are behavioural tests
/// rather than a deletion.
extension CLINotifyProcessIntegrationRegressionTests {
    func testVMNamespaceReportsCloudRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(
            ["vm", "new", "--title", "example"],
            socketLabel: "vm-new"
        )
    }

    func testVMListReportsCloudRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(["vm", "list"], socketLabel: "vm-list")
    }

    func testCloudNamespaceReportsCloudRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(["cloud", "list"], socketLabel: "cloud-list")
    }

    /// The attach entrypoints are separate top-level verbs, so a regression that
    /// restored one of them would not be caught by the `vm` namespace cases.
    func testVMSSHAttachReportsCloudRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(["vm-ssh-attach"], socketLabel: "vm-ssh-attach")
    }

    func testVMPTYAttachReportsCloudRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(["vm-pty-attach"], socketLabel: "vm-pty-attach")
    }

    func testVMPTYConnectReportsCloudRemovedWithoutSocketTraffic() throws {
        try assertHostedServicesUnavailable(["vm-pty-connect"], socketLabel: "vm-pty-connect")
    }

    /// `remotes` and `ai-accounts` share the same removed backend, and share the
    /// same refusal path in the CLI dispatcher.
    func testRemotesAndAIAccountsReportHostedServicesRemoved() throws {
        try assertHostedServicesUnavailable(["remotes", "list"], socketLabel: "remotes-list")
        try assertHostedServicesUnavailable(["ai-accounts"], socketLabel: "ai-accounts")
    }
}
