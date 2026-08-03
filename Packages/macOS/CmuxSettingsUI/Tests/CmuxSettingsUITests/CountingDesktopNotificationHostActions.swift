import Foundation

@testable import CmuxSettingsUI

/// ``SettingsHostActions`` double that counts the desktop-notification
/// authorization calls ``DesktopNotificationAuthorizationModel`` makes.
///
/// The remaining requirements without a protocol default are stubbed out;
/// only the notification bridge records anything.
@MainActor
final class CountingDesktopNotificationHostActions: SettingsHostActions {
    var desktopStatusReads = 0
    var desktopStreamCreations = 0
    var desktopRefreshes = 0
    var desktopStatus: DesktopNotificationAuthorizationState = .unknown

    private let desktopStream: AsyncStream<DesktopNotificationAuthorizationState>

    init(
        desktopStream: AsyncStream<DesktopNotificationAuthorizationState> = AsyncStream {
            $0.finish()
        }
    ) {
        self.desktopStream = desktopStream
    }

    func clearBrowserHistory() {}
    func openConfigInExternalEditor() {}
    func sendFeedback() {}
    func sendTestNotification() {}
    func openSystemNotificationSettings() {}
    func restartApp() {}
    func openBrowserImportFlow() {}
    func requestNotificationAuthorization() {}
    func openTerminalConfigWindow() {}
    func previewNotificationSound(value: String, customFilePath: String) {}

    func desktopNotificationAuthorizationStatus() -> DesktopNotificationAuthorizationState {
        desktopStatusReads += 1
        return desktopStatus
    }

    func desktopNotificationAuthorizationStatusUpdates()
        -> AsyncStream<DesktopNotificationAuthorizationState>
    {
        desktopStreamCreations += 1
        return desktopStream
    }

    func refreshDesktopNotificationAuthorizationStatus() {
        desktopRefreshes += 1
    }
}
