import AppKit
import RoomCore

/// NSApp. Chromium needs its own NSApplication behaviour (RoomCrApplication);
/// the host adds its menu actions here, at the end of the responder chain,
/// because NSApp.delegate is Chrome's AppController.
final class RoomHostApplication: RoomCrApplication {
    private var host: HostController? { RoomApplication.shared.delegate as? HostController }

    @objc func reloadPage(_ sender: Any?) { host?.current?.reload() }
    @objc func goBack(_ sender: Any?) { host?.current?.goBack() }
    @objc func goForward(_ sender: Any?) { host?.current?.goForward() }
    @objc func openLocation(_ sender: Any?) { host?.focusAddressField() }
    @objc func newPage(_ sender: Any?) { host?.newPage() }
}
