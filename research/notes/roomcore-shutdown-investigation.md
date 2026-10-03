# RoomCore shutdown watchdog investigation — 2026-10-03

Status: unresolved intermittent failure; no watchdog timeout, helper grace,
or Chromium check has been relaxed. Successful serial samples do not erase it.

The completion-auth run concurrently with a navigation/ten-page baseline
completed real LoginHandler cancellation and credentials, then exited 2 at
Chrome's 10 s teardown watchdog. The concurrent baseline retained 9 helpers
after its unchanged 5 s grace (later exited), so that sample is rejected too.
The original raw minidump is retained locally in
feature-completion-auth/profile/Crashpad/pending/
87fd01af-915c-43f6-a28b-3da737b9b0ee.dmp.

LLDB reads all 50 threads. The current Content binary had changed for patch
0007; resolve against the preserved audit-after app's matching libcontent
(UUID 4C4C446F-5555-3144-A191-06F082D0775D), not offsets in the new build.
Relevant captured stacks:

- Main thread: PlatformThreadBase::Join → Thread::Stop →
  BrowserProcessIOThread destructor → BrowserMainLoop::ShutdownThreadsAndCleanUp.
- IO thread 18: kernel mach_vm_deallocate → ScopedMachVM::reset_unaligned →
  ScopedMachVM::reset → ChannelMac::ShutDownOnIOThread →
  WillDestroyCurrentMessageLoop → SequenceManagerImpl destruction →
  BrowserIOThreadDelegate destruction.
- Worker 31: WaitForChildToDie → ForceNormalProcessTerminationSync,
  a BLOCK_SHUTDOWN task.
- Two other threads are inside macOS Security keychain database release;
  the captured IO thread is not waiting on those functions.
- Watchdog thread 50 calls DumpWithoutCrashing. Old libchrome_dll has not been
  recovered exactly, so its unsymbolized offsets are not assigned guessed names.

The IO thread snapshot is in a kernel VM deallocation while Mojo tears down
its send/receive buffers (mojo/core/channel_mac.cc:244), not a Room modal,
auth, or find callback. One dump cannot establish how long it spent there,
whether this is resource pressure, or a deterministic deadlock. No justified
small //room fix follows from this evidence yet. Next: repeat the concurrent
pair on the final CDM build, retaining another dump and helper commands if it
fails; compare IO-thread samples before considering any upstream hook.

Serial auth repeats previously passed in 13/10 s. Final CDM engine baseline
passes nav 12.058 s, ten-loaded-page quit 0.354 s, load1 15.50, 26 helpers,
0 left after 5 s, 0 new crash reports, exit 0. These are separate observations.

Concurrent repeat on final CDM engine: auth passed in 11 s, nav passed in
12.745 s; open10 then aborted with signal 6 before reaching ten-loaded-page
readiness. This is a **different failure**, not another shutdown-watchdog
sample. Chrome's FedCmAccountSelectionView::CreateDialogWidget requested a
bubble anchored via BrowserElementsViews::RetrieveView(
kActiveContentsWebViewRetrievalId), which returns null for the Swift host.
BubbleDialogDelegate::CreateBubbleWidget DCHECK at line 207 requires a parent.
Raw fatal stack and minidump are copied under baseline-concurrent-cdm/
quit-failure. It occurred at 08:20:32 EEST while real websites loaded. This
reveals an additional FedCM surface beyond the original 18-feature matrix.
Next work is a real FedCM anchor/parent bridge, followed by a dedicated probe
and baseline; do not conflate it with the earlier IO-thread watchdog.
