import AppKit
import RoomCore

/// NSApp. Chromium needs its own NSApplication behaviour (RoomCrApplication);
/// the host's menu actions live in `HostController`, NSApp's delegate.
final class RoomHostApplication: RoomCrApplication {}
