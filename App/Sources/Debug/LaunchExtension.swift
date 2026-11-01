#if DEBUG
import AppKit

extension AppDelegate {
    /// `-RoomLoadUnpacked <folder>` (5.12): loads an unpacked extension into the first profile once the
    /// engine has its extensions, for checks by hand or by computer use on a throwaway state (the
    /// Settings button's open panel is another process's).
    func loadUnpackedAtLaunch() {
        guard let path = UserDefaults.standard.string(forKey: "RoomLoadUnpacked") else { return }
        Task { @MainActor in
            for _ in 0..<100 {
                if let section = extensions?.sections.first, section.extensions.isReady {
                    do {
                        let id = try await section.extensions.loadUnpacked(at: URL(fileURLWithPath: path, isDirectory: true))
                        NSLog("Room: loaded unpacked %@ from %@", id, path)
                    } catch {
                        NSLog("Room: load unpacked %@ failed: %@", path, String(describing: error))
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            NSLog("Room: load unpacked %@: no extensions section", path)
        }
    }
}
#endif
