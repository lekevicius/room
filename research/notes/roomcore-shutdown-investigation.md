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

The FedCM crash chain is now fixed separately (2a04498), including the primary
Views context needed after the parent exists. Post-fix concurrent direct
open10/auth pair: auth 20 s, exit 0; ten loaded pages, quit 1.881 s, load1 22.12,
26 helpers / 0 left / 0 new crashes, exit 0. This pair did not reproduce the
old watchdog. Baseline script still keeps the original 5 s helper grace.

08:36 EEST machine snapshot (current, not the failed run): 64 GiB physical;
61 GiB used, 19 GiB compressor, 1751 MiB unused; encrypted swap 2461.69 MiB
used / 4096 MiB total. memory_pressure -Q reports 58% system-wide free
(reclaimability differs from unused pages). Load 28.33 / 27.73 / 24.23,
CPU 60.62% idle, 1192 processes / 9160 threads. These describe the test
machine but cannot retrospectively prove pressure caused the earlier timeout.

## Concurrent reproduction and helper capture — 09:00–09:10 EEST

Engine eb55062 / host 338b370, immutable audit-activation app. One bounded
three-browser exercise opened ten real pages per browser. Total 77.941 s:

| Group | Readiness | Outcome |
|---|---|---|
| 1 | Stack Overflow still loading at 63 s | Rejected fixture; not a quit pass |
| 2 | All ten loaded at 45 s | Watchdog exit 2 |
| 3 | All ten loaded at 42 s | Watchdog exit 2 |

Raw evidence: baseline-shutdown-stress/group-{1,2,3}. Both failed browsers
were sampled for 2 s after the terminate marker was 3 s old. Main threads
waited in BrowserProcessIOThread::ProcessHostCleanUp → WaitForExitWithTimeout;
IO threads were still pumping normally. The only explicit wait in that
function is for network::mojom::NetworkService, allowing its cookies/cache
to flush before other child processes are terminated (upstream
content/browser/browser_process_io_thread.cc:117). It has a 10 s bound, while
the separate Chrome teardown watchdog also has a 10 s deadline.

The final watchdog dumps differ: group 3 still waits for the network process;
group 2 has advanced to ThreadPoolImpl::Shutdown, with a BLOCK_SHUTDOWN worker
in WaitForChildToDie / ForceNormalProcessTerminationSync. The old dump's
IO-thread VM-deallocation snapshot was therefore not sufficient to identify
the dominant delay. All helpers eventually exited; none remained at 09:02.
No watchdog or grace was changed.

Dumps: group 2 539a05ee-336f-4bfc-8095-1b086706f7bd.dmp; group 3
4bb19154-cfaa-4043-9098-483272b2bf02.dmp. LLDB used matching audit-activation
libraries: libcontent UUID 4C4C44F9-5555-3144-A1C5-85BCC71FC018 and
libchrome_dll UUID 4C4C44BB-5555-3144-A1CC-1683BA2C1C41. Complete symbolized
stacks are beside each group's live sample. A few system-library frames have
LLDB shared-cache mapping warnings; the named Chromium frames match UUIDs.

One targeted repeat (baseline-shutdown-helpers, 67.291 s) also sampled the
network helper while its browser waited. Group 1 again failed external-page
readiness. Groups 2/3 passed all ten pages and quit in 6.017 / 5.691 s, with
27 / 26 helpers observed, 0 left, 0 new crashes, exit 0. Both helpers were
already in ChildProcess destruction → ThreadPoolImpl::Shutdown →
TaskTracker::CompleteShutdown. Two worker threads per helper remained in
ThreadFunc → _pthread_set_properties_self → __bsdthread_ctl for 58/60 and
59/60 samples (group 2), 47/48 each (group 3). Group 2 then briefly executed
ImportantFileWriter's BLOCK_SHUTDOWN atomic write / File::Flush.

Source correspondence: platform_thread_posix.cc:ThreadFunc sets the default
thread type before delegate->ThreadMain; platform_thread_apple.mm maps
kBackground to QOS_CLASS_BACKGROUND. WorkerThread creates its priority boost
only inside RunWorker, after ThreadMain. These samples support investigating
a worker-start/QoS delay before the existing shutdown boost can run. They do
not establish that this is the cause of both watchdogs, an OS bug, or a fix.
Do not disable background scheduling, data flushing or the watchdog as a
speculative workaround. No narrow //room fix is justified yet.

Next diagnostic: collect network-helper stacks during an actual exit-2
reproduction (the helper capture above was a slow successful quit), and
compare worker-start/QoS behavior with an unmodified Chromium host or a
minimal thread-start reproducer before considering an upstream hook. Preserve
memory/load and child commands with that capture. The quit timing tool now
writes failure.json with markers, helper commands, dumps and exit status for
all rejected runs. An exit-2 child fixture verified that diagnostics are
retained, the runner still fails, and no passing timing receipt is emitted.
