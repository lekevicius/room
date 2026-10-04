// Isolated diagnostic for worker creation before/after shutdown begins.
// Uses the same component libbase as Room, without starting a browser.
#include <cstdio>
#include <memory>
#include <mach/mach.h>
#include <pthread/qos.h>
#include <unistd.h>

#include "base/at_exit.h"
#include "base/check.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/task/task_runner.h"
#include "base/task/thread_pool/thread_pool_impl.h"
#include "base/threading/scoped_blocking_call.h"
#include "base/memory/scoped_refptr.h"
#include "base/synchronization/waitable_event.h"
#include "base/task/thread_pool/environment_config.h"
#include "base/task/thread_pool/sequence.h"
#include "base/task/thread_pool/task_tracker.h"
#include "base/task/thread_pool/worker_thread.h"
#include "base/threading/platform_thread.h"
#include "base/threading/thread.h"
#include "base/time/time.h"

namespace {
using base::internal::RegisteredTaskSource;
using base::internal::WorkerThread;
struct Observation {
  base::WaitableEvent entered;
  base::WaitableEvent fetched;
  base::ThreadType entry_type = base::ThreadType::kDefault;
  base::ThreadType fetch_type = base::ThreadType::kDefault;
  qos_class_t entry_qos = QOS_CLASS_UNSPECIFIED;
};
class Delegate : public WorkerThread::Delegate {
 public:
  explicit Delegate(Observation* observation) : observation_(observation) {}
  void OnMainEntry(WorkerThread*) override {
    observation_->entry_type = base::PlatformThread::GetCurrentThreadType();
    CHECK_EQ(pthread_get_qos_class_np(pthread_self(), &observation_->entry_qos,
                                     nullptr), 0);
    observation_->entered.Signal();
  }
  RegisteredTaskSource GetWork(WorkerThread*) override {
    observation_->fetch_type = base::PlatformThread::GetCurrentThreadType();
    observation_->fetched.Signal();
    return nullptr;
  }
  RegisteredTaskSource SwapProcessedTask(RegisteredTaskSource,
                                        WorkerThread*) override {
    CHECK(false);
  }
  base::TimeDelta GetSleepTimeout() override { return base::TimeDelta::Max(); }
 private:
  const raw_ptr<Observation> observation_;
};

bool Observe(bool start_during_shutdown,
             scoped_refptr<base::SingleThreadTaskRunner> io_runner) {
  base::internal::TaskTracker tracker;
  // Keep shutdown incomplete so the worker is allowed to request work.
  auto sequence = base::MakeRefCounted<base::internal::Sequence>(
      base::TaskTraits{base::TaskShutdownBehavior::BLOCK_SHUTDOWN}, nullptr,
      base::internal::TaskSourceExecutionMode::kParallel, base::ThreadType::kDefault);
  auto registered = tracker.RegisterTaskSource(std::move(sequence));
  if (start_during_shutdown) {
    tracker.StartShutdown();
  }
  Observation observation;
  auto worker = base::MakeRefCounted<WorkerThread>(
      base::ThreadType::kBackground, std::make_unique<Delegate>(&observation),
      tracker.GetTrackedRef(), 0);
  CHECK(worker->Start(io_runner));
  CHECK(observation.entered.TimedWait(base::Seconds(5)));
  worker->WakeUp();
  CHECK(observation.fetched.TimedWait(base::Seconds(5)));
  worker->JoinForTesting();
  printf("{\"shutdown_started_before_create\":%s,\"entry_background\":%s,"
         "\"entry_qos\":%u,\"get_work_background\":%s}\n",
         start_during_shutdown ? "true" : "false",
         observation.entry_type == base::ThreadType::kBackground ? "true" : "false",
         static_cast<unsigned>(observation.entry_qos),
         observation.fetch_type == base::ThreadType::kBackground ? "true" : "false");
  return !start_during_shutdown ||
         observation.entry_type >= base::ThreadType::kDefault;
}
// Inspect an already-blocked task after ThreadPool has notified its groups of
// shutdown, but before CompleteShutdown waits. No timeout determines success.
int ReadPriority(mach_port_t thread) {
  thread_extended_info_data_t info{};
  mach_msg_type_number_t count = THREAD_EXTENDED_INFO_COUNT;
  CHECK_EQ(thread_info(thread, THREAD_EXTENDED_INFO,
                       reinterpret_cast<thread_info_t>(&info), &count), KERN_SUCCESS);
  return info.pth_priority;
}
struct BlockedObservation {
  base::WaitableEvent entered;
  BlockedObservation() { CHECK_EQ(pipe(release_pipe), 0); }
  ~BlockedObservation() {
    close(release_pipe[0]);
    close(release_pipe[1]);
  }
  int release_pipe[2];
  bool native_override = false;
  pthread_t pthread = nullptr;
  mach_port_t thread = MACH_PORT_NULL;
  int before_priority = -1;
  int shutdown_priority = -1;
};
class ShutdownTracker : public base::internal::TaskTracker {
 public:
  explicit ShutdownTracker(BlockedObservation* observation)
      : observation_(observation) {}
 protected:
  void BeginCompleteShutdown(base::WaitableEvent&) override {
    pthread_override_t override = nullptr;
    if (observation_->native_override) {
      override = pthread_override_qos_class_start_np(
          observation_->pthread, QOS_CLASS_USER_INITIATED, 0);
      CHECK(override);
    }
    observation_->shutdown_priority = ReadPriority(observation_->thread);
    if (override) {
      CHECK_EQ(pthread_override_qos_class_end_np(override), 0);
    }
    const char released = 1;
    CHECK_EQ(write(observation_->release_pipe[1], &released, 1), 1);
  }
 private:
  const raw_ptr<BlockedObservation> observation_;
};
bool ObserveBlockedBeforeShutdown(bool single_thread, bool skip_on_shutdown,
                                  bool native_override) {
  BlockedObservation observation;
  observation.native_override = native_override;
  base::internal::ThreadPoolImpl pool(
      "", std::make_unique<ShutdownTracker>(&observation));
  pool.Start(base::ThreadPoolInstance::InitParams(4), nullptr);
  const base::TaskTraits traits{
      base::MayBlock(),
      base::TaskPriority::BEST_EFFORT,
      skip_on_shutdown ? base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN
                       : base::TaskShutdownBehavior::BLOCK_SHUTDOWN};
  scoped_refptr<base::TaskRunner> runner = single_thread
      ? pool.CreateSingleThreadTaskRunner(traits,
            base::SingleThreadTaskRunnerThreadMode::SHARED)
      : pool.CreateTaskRunner(traits);
  CHECK(runner->PostTask(FROM_HERE, base::BindOnce([](BlockedObservation* state) {
    base::ScopedBlockingCall block(FROM_HERE, base::BlockingType::WILL_BLOCK);
    state->pthread = pthread_self();
    state->thread = pthread_mach_thread_np(state->pthread);
    state->before_priority = ReadPriority(state->thread);
    state->entered.Signal();
    char released = 0;
    CHECK_EQ(read(state->release_pipe[0], &released, 1), 1);
  }, base::Unretained(&observation))));
  CHECK(observation.entered.TimedWait(base::Seconds(5)));
  const int normal_priority = ReadPriority(pthread_mach_thread_np(pthread_self()));
  pool.Shutdown();
  pool.JoinForTesting();
  printf("{\"blocked_before_shutdown\":true,\"single_thread\":%s,"
         "\"skip_on_shutdown\":%s,\"native_override\":%s,\"normal_priority\":%d,"
         "\"before_priority\":%d,\"shutdown_priority\":%d}\n",
         single_thread ? "true" : "false", skip_on_shutdown ? "true" : "false",
         native_override ? "true" : "false", normal_priority, observation.before_priority, observation.shutdown_priority);
  return observation.shutdown_priority >= normal_priority;
}
}  // namespace

int main(int argc, char** argv) {
  alarm(15);
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::FeatureList::InitInstance("", "");
  CHECK(base::internal::CanUseBackgroundThreadTypeForWorkerThread());
  if (base::CommandLine::ForCurrentProcess()->HasSwitch("blocked-before-shutdown")) {
    return ObserveBlockedBeforeShutdown(
        base::CommandLine::ForCurrentProcess()->HasSwitch("single-thread"),
        base::CommandLine::ForCurrentProcess()->HasSwitch("skip-on-shutdown"),
        base::CommandLine::ForCurrentProcess()->HasSwitch("native-override")) ? 0 : 2;
  }
  base::Thread service("ProbeService");
  base::Thread::Options options;
  options.message_pump_type = base::MessagePumpType::IO;
  CHECK(service.StartWithOptions(std::move(options)));
  const bool before = Observe(false, service.task_runner());
  const bool during = Observe(true, service.task_runner());
  service.Stop();
  alarm(0);
  // A failing diagnostic establishes the startup type, not a shutdown hang.
  return before && during ? 0 : 2;
}
