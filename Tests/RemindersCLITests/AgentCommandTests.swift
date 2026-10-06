// ABOUTME: Unit tests for launchctl bootout result handling in the agent command.
// ABOUTME: Keeps uninstall idempotent without claiming success while a service remains loaded.

import Testing
@testable import reminders

@Suite("agent command")
struct AgentCommandTests {

    @Test func installAcceptsACustomTailscaleServePath() throws {
        let command = try AgentCommand.Install.parse([
            "--tailscale-serve-path", "/custom/reminders-mcp",
        ])

        #expect(command.tailscaleServePath == "/custom/reminders-mcp")
    }

    @Test func installWithoutAPathKeepsTheExistingServeArguments() throws {
        let command = try AgentCommand.Install.parse([])

        #expect(command.tailscaleServePath == nil)
        #expect(AgentCommand.launchAgentServeArguments(path: nil).isEmpty)
    }

    @Test(
        "tailscale serve paths must be non-root mount paths",
        arguments: [
            "reminders",
            "/",
            "/reminders/",
            "/reminders//nested",
            "/reminders?query=yes",
            "/reminders#fragment",
            "/reminders path",
            "/reminders/../other",
            "/./reminders",
        ]
    )
    func invalidTailscaleServePath(path: String) {
        #expect(throws: (any Error).self) {
            _ = try AgentCommand.Install.parse([
                "--tailscale-serve-path", path,
            ])
        }
    }

    @Test func tailscaleServeArgumentsMountTheLoopbackServerAtTheCustomPath() {
        #expect(
            AgentCommand.tailscaleServeArguments(path: "/custom/reminders-mcp") == [
                "serve",
                "--bg",
                "--https=443",
                "--set-path=/custom/reminders-mcp",
                "http://127.0.0.1:7364",
            ]
        )
    }

    @Test func customPathFlowsIntoTheLaunchAgentArguments() {
        #expect(
            AgentCommand.launchAgentServeArguments(path: "/custom/reminders-mcp") == [
                "--bind", "127.0.0.1",
                "--port", "7364",
                "--external-base-path", "/custom/reminders-mcp",
            ]
        )
    }

    @Test func detectsFunnelOnHTTPS443EvenWithACommandWarning() throws {
        let status = """
        Warning: client and server versions differ
        {"AllowFunnel":{"host.example.ts.net:443":true}}
        """

        #expect(try AgentCommand.hasFunnelOnHTTPSPort(statusOutput: status))
    }

    @Test func acceptsServeStatusWithoutFunnel() throws {
        let status = """
        {"TCP":{"443":{"HTTPS":true}},"Web":{"host.example.ts.net:443":{}}}
        """

        #expect(try !AgentCommand.hasFunnelOnHTTPSPort(statusOutput: status))
    }

    @Test func acceptsEmptyServeStatusAfterACommandWarning() throws {
        let status = """
        Warning: client and server versions differ
        null
        """

        #expect(try !AgentCommand.hasFunnelOnHTTPSPort(statusOutput: status))
    }

    @Test func failedInstallationRunsRollbackAndRethrowsTheOriginalError() {
        struct InstallFailure: Error {}
        var didRollback = false

        do {
            try AgentCommand.performInstallation {
                throw InstallFailure()
            } rollback: {
                didRollback = true
            }
            Issue.record("Expected installation to fail")
        } catch {
            #expect(error is InstallFailure)
        }

        #expect(didRollback)
    }

    @Test func successfulBootoutIsAccepted() throws {
        try AgentCommand.validateBootout(
            status: 0,
            output: "",
            serviceStillLoaded: true
        )
    }

    @Test func missingServiceIsAccepted() throws {
        try AgentCommand.validateBootout(
            status: 3,
            output: "Could not find service",
            serviceStillLoaded: false
        )
    }

    @Test func failedBootoutWhileLoadedThrows() {
        #expect(throws: (any Error).self) {
            try AgentCommand.validateBootout(
                status: 5,
                output: "Permission denied",
                serviceStillLoaded: true
            )
        }
    }
}
