// Phase 2.8b: hands a link to Room the way another app does when it opens a
// link with a chosen application (NSWorkspace.open(_:withApplicationAt:)).
// Prints the time just before the call (seconds since 1970) on stdout.
// Usage: open-with-workspace <Room.app> <url>
import AppKit

let app = URL(fileURLWithPath: CommandLine.arguments[1])
let url = URL(string: CommandLine.arguments[2])!
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
print(String(format: "%.6f", Date().timeIntervalSince1970))
let done = DispatchSemaphore(value: 0)
NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
    if let error { FileHandle.standardError.write(Data("open failed: \(error)\n".utf8)) }
    done.signal()
}
done.wait()
