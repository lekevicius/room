// B-47: sends one AppleEvent to one process, addressed by pid, never by
// bundle id. Every Debug build shares app.room.desktop.dev (5.0a; the Release
// app and the DMG are app.room.desktop); an event addressed by bundle id goes
// to whichever copy LaunchServices picks, and launches one when none runs. An event
// addressed by pid goes to that process or fails (procNotFound) when it has
// exited; nothing is ever launched. (JXA's Application(pid).activate() was
// tried first and relaunched the app when the spike quit mid-call.)
// Usage: room-ae activate|quit <pid>   (exit 0 delivered, 1 not delivered)
// Compiled on demand by scripts/lib/room-process.sh into build/tools.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let pid = pid_t(args[2]) else {
    FileHandle.standardError.write(Data("usage: room-ae activate|quit <pid>\n".utf8))
    exit(2)
}
let target = NSAppleEventDescriptor(processIdentifier: pid)
let event: NSAppleEventDescriptor
switch args[1] {
case "activate":  // 'misc'/'actv', what AppleScript's `activate` sends
    event = NSAppleEventDescriptor(eventClass: AEEventClass(kAEMiscStandards), eventID: AEEventID(kAEActivate),
                                   targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                   transactionID: AETransactionID(kAnyTransactionID))
case "quit":  // 'aevt'/'quit', the ⌘Q path
    event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
                                   targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                   transactionID: AETransactionID(kAnyTransactionID))
default:
    exit(2)
}
// A process that is still launching is not yet eligible for events
// (procNotFound until NSApplication checks in; up to ~9 s on RoomCore under a
// build's load), so retry while it lives: 1 s for activate, 15 s for quit.
let deadline = Date().addingTimeInterval(args[1] == "quit" ? 15 : 1)
while true {
    do {
        _ = try event.sendEvent(options: [.noReply], timeout: 5)
        exit(0)
    } catch {
        let notYet = (error as NSError).code == Int(procNotFound)
        if notYet && kill(pid, 0) == 0 && Date() < deadline {
            usleep(200_000)
            continue
        }
        FileHandle.standardError.write(Data("room-ae \(args[1]) \(pid): \(error)\n".utf8))
        exit(1)
    }
}
