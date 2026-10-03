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

## Control comparisons — 09:18–09:31 EEST

A longer helper capture on the same Room host (baseline-shutdown-helpers-watchdog)
finished all three ten-loaded-page runs: 5.474 / 2.919 / 6.969 s, 24 / 26 / 27
helpers, 0 left, 0 new crashes, exit 0. It did **not** reproduce the watchdog.
The longer requested sample ended when its helper exited; group 3 contains
only five usable snapshots. Two workers were in the same initial QoS call in
four of five samples, then one advanced to the persistent file flush. No
stronger root-cause claim follows. Machine before the exercise: load
8.99 / 20.34 / 31.16, CPU 56.99% idle, 62 GiB used, 18 GiB compressor,
1367 MiB unused, 1190 processes / 9059 threads.

Controls deliberately distinguish configurations:

| Control | Observation | Limit |
|---|---|---|
| Native pthread QoS operation | 32 user-initiated calls: max 0.002 ms; 32 background calls: median 0.215 ms, max 0.238 ms; all return 0 | No Chromium task pool, utility sandbox or disk flush; does not reproduce the delay |
| Installed Google Chrome 154.0.8037.93, three fresh profiles, same URLs | Browser.close exits 0 in 0.880 / 0.888 / 0.919 s | NYTimes still interactive in all three at 63 s; all are rejected as ten-loaded-page baselines. Optimized build and patch version differ |
| Fork component libraries, Chromium stock entry/window factory, staged bundle | One complete ten-page run: exit 0, 1.091 s (baseline-shutdown-stock-window-libraries/group-1) | Other two Page.enable commands timed out; rejected, not quit measurements. One pass does not establish a host-specific cause |

The stock-entry control is **not an unmodified Chromium build**: branding and
the eight patches remain linked, including CDM registration factories. It
bypasses RoomApplication.run, its network policy, Swift host and installed
RoomBrowserWindow factory. This removes the host/window boundary while keeping
the component configuration. The installed Chrome control is unmodified but
not the same build. Neither control reproduced an exit-2 watchdog.

Diagnostic source is retained in roomcore-shutdown-comparison.mjs (Node 22's
built-in WebSocket; isolated profiles, CDP Browser.close, bounded 180 s) and
roomcore-qos-probe.c (64 total native calls, 15 s alarm). Comparison readiness
requires a page-load event plus complete document state, so it is stricter in
a different way than the Room isLoading check; it cannot replace that baseline.
The driver now exits nonzero for incomplete/setup-failed samples and records
final exit separately from a clean shutdown measurement.

Preparation failures are retained too: direct out/dev startup exceeded the
initial 15 s endpoint allowance; with 60 s allowance it reached CDP but all
three Page.enable commands exceeded 20 s. A cloned bundle with the stock entry
could not add a Libraries rpath (no Mach-O header space), then aborted in dyld
for missing libc++_chrome. The corrected run used DYLD_LIBRARY_PATH pointing
only to that bundle's staged Libraries. These are control-setup failures,
not Room host crashes. The product bundle and source were unchanged.

Next step remains capturing the network helper during an actual watchdog,
rather than treating a slow successful sample as its cause. Avoid repeated
unqualified stress runs: retain the helper across the full deadline plus
machine state, and only consider a narrow engine/upstream change once the
blocked operation is established. Watchdog, helper grace and data durability
remain unchanged. Latest PR CI compile/unit checks passed in 70 / 78 s.

## Early teardown and leftover-renderer capture — 09:44–09:52 EEST

Added opt-in --diagnose-shutdown to the strict quit runner. It logs the
network-service wait and samples that helper from the termination marker;
these receipts explicitly identify diagnostic overhead. On cleanup failure,
one surviving helper is sampled after the unchanged five-second check.
No sampling occurs in normal baseline mode.

An initial browser+network capture (baseline-shutdown-targeted) began
28 / 49 / 145 ms after termination markers. All ten pages loaded; browsers
exited 0 in 6.333 / 3.699 / 6.633 s, but 8 / 11 / 9 helpers remained at the
unchanged grace deadline. All samples are rejected. Network waits were
5217 / 1410 / 5457 ms. No new crash reports or watchdog. Browser sampling was
removed from the final tool to reduce observer interference; a watchdog
already provides the main-process minidump when it fires.

Network-only capture (baseline-shutdown-network-only) still rejected all three:
6.731 / 8.115 / 7.656 s browser exits, 6 / 4 / 6 helpers left, 0 new crashes,
exit 0; network waits 5933 / 6913 / 6813 ms. One sampler remained running at
each browser exit, so instrumentation overhead is still a limitation. All
helpers later exited. This does not prove the unsampled timing distribution.
Two workers in the first network capture stayed in initial QoS setting in
all 365 samples, while main waited for the network ThreadPool to drain.

A leftover renderer (75080, reparented to launchd) was sampled after the
failure: its main and compositor threads waited on synchronous GPU channel
DestroyCommandBuffer during disconnect. Its IO thread was in
ChannelMac::ShutDownOnIOThread → ScopedMachVM reset → mach_vm_deallocate for
all 67 samples. Another renderer (75077) was processing an IPC endpoint error
on its IO thread while its main waited on the same GPU disconnect path.
Thus the evidence includes both network-worker startup and renderer/Mojo
cleanup delays; do not collapse these into one proved cause.

One diagnostic-only --disable-gpu exercise (baseline-shutdown-software)
obtained browser exits 0 in 2.530 / 3.576 s with 0 leftover helpers, but both
were rejected for the concurrent group's crash report. The third browser
aborted before readiness. A renderer first DCHECKed in Blink
LayoutObject::AssertLaidOut (layout_object.h:518, clientWidth/layout path),
then the browser DCHECKed at sad_tab_controller.cc:32 because Room has no
BrowserView. This is a separate actionable hardening defect: renderer loss
must not take down the host. No conclusion that disabling GPU fixes teardown
is warranted. The flag is absent from production configuration.

Next: fix SadTab creation through the smallest available factory seam and
add an intentional renderer-crash/reload probe. The underlying Blink layout
failure remains unmodified; its dump/log are preserved. B-16 tracks the
unresolved teardown reliability issue; B-8 now reflects the existing native
termination option. Prior checkpoint CI passes 70 / 86 s.


## Deterministic loopback comparison — 10:14–10:17 EEST

The SadTab renderer-loss containment described above is fixed in 0f87b84;
intentional crash/reload and the required real-site serial baseline pass.
It does not repair the underlying Blink renderer layout defect or the
concurrent teardown issue.

Added scripts/roomcore-shutdown-local.py and a host-only RoomSpikeURLsJSON
option. Ten distinct *.localhost origins, served exclusively on 127.0.0.1,
each complete a persistent cookie, 65,536-character localStorage write, 65,536-character IndexedDB
transaction, and a 128 KiB cached HTTP fetch before their ready title. A
bounded 640×360 canvas animation exercises the compositor. This is a small
controlled corpus, not a recreation of the real websites. Bad/incomplete
fixture state fails the existing runner. Default open10 still uses the ten
external sites; receipts identify which corpus ran.

| Host / three concurrent browsers | Ready seconds | Quit seconds | Result |
|---|---|---|---|
| Room, engine 0f87b84 plus test-only host changes | 28 / 27 / 26 | 1.028 / 1.596 / 2.336 | All ten fixture titles ready per browser; 28 / 27 / 27 helpers observed; 0 left after unchanged 5 s grace, 0 new crash reports, all exit 0 |
| Stock Chromium window entry, same current fork component libraries | 22.500 / 24.095 / 22.468 | 5.107 / 3.790 / 4.585 | All ten fixture titles ready per browser; 0 helpers left after 5 s, 0 new crash reports, all exit 0 |

No stack sampling ran. Room uses the native NSApp terminate marker; stock
uses Browser.close over CDP, opens its tabs sequentially through CDP, and
has Chrome UI/default services. The stock control is **not unmodified
Chromium** and these are not an apples-to-apples performance ranking. Its
bundle is build/roomcore/audit-stock-local/Room.app: cloned current package,
stock out/dev executable and Info.plist, re-signed ad hoc. DYLD_LIBRARY_PATH
points at that same bundle's Libraries. Prior controls used an older snapshot;
this control uses the SadTab engine libraries.

Machine before Room: load 14.57/14.94/26.00, 49.17% CPU idle, 63 GiB used,
18 GiB compressor, 164 MiB unused; 1196 processes/9158 threads. Before stock:
load 98.30/47.33/37.73, 56.92% CPU idle, 60 GiB used, 19 GiB compressor,
3294 MiB unused; 1167 processes/9001 threads. Load history/launch order and
instrumentation differ. Total exercise durations 45.176 / 35.090 s. Raw
receipts and machine snapshots are in baseline-shutdown-local-room and
baseline-shutdown-local-stock. Python/Node syntax checks pass; host rebuilt
in 8.6 s, strict ad-hoc signature valid. CI for 0f87b84 passes 78/81 s.

This bounded control does not reproduce a watchdog or helper-grace failure,
and therefore supplies no basis for changing shutdown scheduling or limits.
Retain B-16 open. Further repetition of this same corpus is not useful without
an additional discriminating hypothesis. The real-site failures remain valid
and their retained minidumps/helper stacks are the next source of evidence.


## Process-census overhead and fresh watchdogs — 10:36–10:43 EEST

A concrete observer concern: the original Room runner invokes ps -axo
pid=,ppid=,command= over the whole machine on every loop, then sleeps 20 ms.
Thirty isolated censuses took 1.771 s wall / 0.519475 s child user CPU /
1.197847 s child system CPU; median 58.790 ms, max 65.939 ms. Thus the
original actual cadence is census time plus 20 ms, not 50 snapshots/s.
Three concurrent runners add substantial process-enumeration work.

Added diagnostic-only --process-snapshot-ms (default 0 preserves the original
behavior), plus measured census count/wall time in success and failure
receipts. It does not alter the 120 s run deadline, 10 s Chrome watchdog,
5 s helper grace or the normal 20 ms exit poll between censuses.

One bounded paired comparison used current engine 0f87b84 / host a4f8c25,
fresh profiles and the same ten external URLs, without stack sampling:

| Cadence | Outcome | Census count / cumulative census wall seconds per runner |
|---|---|---|
| 250 ms after each census | Three loaded-page quits 5.010 / 3.331 / 3.930 s; 26 / 26 / 24 helpers observed, 0 left, 0 crash reports, exit 0; whole exercise 59.551 s | 107/27.227; 102/27.177; 103/26.964 |
| Original (0 ms additional interval) | Three browser watchdog exits 2; runners correctly exit 1; whole exercise 57.317 s. Groups 2/3 show 10 pages and 0 loading; group 1 still loading and independently rejected | 255/48.490; 267/49.827; 239/47.607 |

The runs are sequential, not randomized, and live sites differ: Stack Overflow
returned a challenge in the second run (including the two non-loading pages).
Before the first: load 8.54/15.46/21.27, CPU 60.39% idle, 63G physical used,
31G compressor, swap 2453.69M. Before the second: load 97.40/57.80/37.93,
CPU 54.14% idle, 61G used, 21G compressor, swap 5719.00M. These are confounders.
The pass/failure contrast does not prove census overhead causes the watchdog,
and no engine or default-runner workaround is adopted.

Fresh minidumps are symbolized with the immutable audit-sadtab Room.app.
Content UUID 4C4C44F9-5555-3144-A1C5-85BCC71FC018;
Chrome UUID 4C4C44C6-5555-3144-A108-51D1A4AC6AE8. Groups 1/3 main threads wait
in BrowserProcessIOThread::ProcessHostCleanUp for the network service.
Group 2 waits in ThreadPoolImpl::Shutdown; one background worker is in
ScopedBoostPriorityBase::AdoptAsLease via MaybeUpdateThreadType, but one
snapshot gives no duration and does not establish that worker as the cause.
Unlike an older dump, this group 2 trace does not identify WaitForChildToDie.
All three include TearDownWatchdog::ThreadMain. Some system-library frames
have shared-cache mapping warnings; named Chromium modules match UUIDs.

Dumps under baseline-shutdown-default-census/group-{1,2,3}/run-1/profile/
Crashpad/pending: 1c069b42-a00a-40a3-b36e-b8928247b9ee,
da634815-8795-4558-b9da-32c9f7c2981e, 821c349d-d578-4610-b623-6b8fcc7ffc8a.
Complete backtraces, failure receipts, process lists and machine snapshots
are retained; all helpers later exited. Low-census evidence is under
baseline-shutdown-low-census. This reproduces B-16 on the latest engine
without live stack sampling, rather than resolving it.

Next discriminating step: reduce observer work itself before more stress.
A diagnostic observer can use macOS libproc child-PID enumeration and process
identity, obtaining command lines only for newly observed children; validate
it against known child creation/exit and PID identity before using it on a
browser. The installed SDK exposes proc_listchildpids, proc_pidpath and
proc_pidinfo/PROC_PIDTBSDINFO including start time. Do not silently weaken
helper detection, change default baselines, or attribute failures solely to
ps without an adequately controlled observation. No further unqualified
repetition of the real-site/census pair is useful.


## Native process observer — 11:07 EEST

Added opt-in --process-observer libproc. The default remains ps. Native
observation enumerates children through proc_listchildpids, identifies each
PID by its start time through PROC_PIDTBSDINFO, and reads its executable path.
Known descendants remain tracked after reparenting and are checked for a
fork-to-exec transition. New helper command lines are obtained in targeted
batches; polling does not repeatedly request every process's arguments.
Unknown observation errors fail the run rather than becoming an empty set.
Receipts identify the observer, query count and (after the browser exercise)
helper start identities. All existing watchdogs, polling and grace remain.

Local lifecycle fixture passes creation, delayed exec, reparenting, exit and
a synthetic mismatched-start-time rejection for a still-live PID. Final run:
100 snapshots in 0.001615 s, one command query. The full runner rejects a
compiled helper deliberately left alive beyond the unchanged 5 s grace:
helpers_left=1, browser exit0, runner failure, observer_error=null. Earlier
fixture setup tried copying system sleep: protected flags then platform-binary
termination made that unsuitable; the final test compiles an ordinary sleeper.
No Room engine defect was inferred from that setup failure. Reusable local
validation: python3 scripts/roomcore-process-observer-test.py.

One bounded three-browser real-site comparison, without stack sampling:

| Group | Ready seconds | Quit seconds | Helpers observed / left | Native snapshots / census wall seconds | Targeted command queries |
|---|---|---|---|---|---|
| 1 | 37 | 7.723 | 26 / 0 | 1566 / 11.104 | 14 |
| 2 | 37 | 2.885 | 27 / 0 | 1403 / 10.253 | 15 |
| 3 | 36 | 1.326 | 26 / 0 | 1314 / 10.812 | 15 |

All ten pages were non-loading, Stack Overflow had its expected questions
title in this run, all browsers exit0, zero new crash reports. Exercise
61.159 s; machine before: load15.26/13.24/19.75, CPU57.30%idle, 55G used,
14G compressor, 8335M unused, swap5719M, 987 processes/8637 threads. Evidence:
baseline-shutdown-libproc. Existing engine0f87b84/hosta4f8c25 was unchanged.

This observer performs many more snapshots with less cumulative census wall
time than the earlier full-ps exercise (10–11 s versus48–50 s), but the live
sites and machine state differ. The 7.723 s quit is still close to the 10 s
watchdog. B-16 is not fixed, and no causality is assigned to ps. Future bounded
diagnostics can use this validated observer while retaining failed samples;
there is no reason to repeat the observer lifecycle or earlier control runs.

## Read-only network thread states — 11:18 EEST

Added opt-in --network-thread-states (requires --process-observer libproc).
It queries libproc thread information every 250 ms, without suspending the
process or collecting live stacks. The original default observer, polling,
watchdog and helper grace remain unchanged. Receipt counts and query wall time
make the added observer work visible. Process start identity is checked before
and after reading threads; unexpected errors fail the run.

Bounded three-browser exercise, existing engine0f87b84/hosta4f8c25, total87.791s:

| Group | Outcome | Network wait | Thread queries / wall seconds |
|---|---|---|---|
| 1 | Ten non-loading pages, quit1.148s,27helpers/0left/0crashes,exit0 | 582ms | 129 /0.705172 |
| 2 | Ten non-loading pages, quit2.193s,25helpers/0left/0crashes,exit0 | 1668ms | 129 /1.041409 |
| 3 | Watchdog exit2; independently rejected for Stack Overflow still loading at63s | 3831ms | 237 /0.144527 |

Evidence: baseline-shutdown-thread-states. Group3 dump
42a738ab-9ce4-43c6-9241-ea3119b6f79a is symbolized against the matching retained
audit-sadtab component libraries. At the watchdog deadline, main is in
TaskTracker::CompleteShutdown, not ProcessHostCleanUp. Thread38 is executing
PolicyLoaderMac::InitOnBackgroundThread → FilePathWatcher::Watch →
FilePathWatcherKQueue::FileDescriptorForPath → open. The task uses Chrome's
BEST_EFFORT/MayBlock policy-loader sequence, and its stack is RunSkipOnShutdown.
An already-running SKIP_ON_SHUTDOWN task still contributes to shutdown waiting.
This snapshot identifies unfinished work; it does not measure the duration of
open or prove why it was delayed. No policy-loader or scheduling change follows.

Group3 network-helper teardown has18 snapshots over4.436898s. Two entries
named ThreadPoolBackgroundWorker stay at priority4; each has3 waiting and15
running-state samples with unchanged exported CPU counters. Thus these entries
had reached thread naming, unlike the earlier unnamed initial-QoS stacks. The
running-state classification is not evidence of CPU execution, and these raw
observations do not prove starvation. The helper exits before the browser's
later watchdog. Capturing only network threads cannot explain the entire wait.

Observer qualification: PROC_PIDLISTTHREADS returns reusable thread handles,
not unique thread IDs. The installed mach/thread_info.h calls the corresponding
THREAD_IDENTIFIER_INFO field thread_handle. Apple's kernel dispatch separately
selects unique IDs for other flavors:
https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c.
The raw experiment's preliminary field named id contains handles, including
zero entries; do not aggregate CPU counters across a handle's lifetime.
Committed output labels thread_handle/identity_kind explicitly, counts omitted
zero handles, and records process identity. No private libproc flavor is used.

Local fixture cross-checks each libproc handle/name against its own Mach
THREAD_IDENTIFIER_INFO and observes creation/exit. Sixteen sequential threads
reuse one handle;38 snapshots take0.000940s query time,0.010632s fixture wall.
Two fixture corrections were required: a pthread_self pointer differs from the
libproc handle, and Python join returns before OS teardown fully finishes.
The fixture now uses the SDK-defined identity structure and bounded exit
observation. Neither fixture failure was a Room failure. Python compilation and
whitespace checks pass; CI5a34664 build passed89s.

B-16 remains open. The next discriminating measurement should cover browser
workers as well as the network service during teardown, with duration evidence
for the policy-loader file operation versus runnable worker delay. Existing
network-only captures and one final stack cannot justify a priority workaround,
skipping policy work, or changing the watchdog. Preserve failed samples and
avoid another unqualified stress loop.
