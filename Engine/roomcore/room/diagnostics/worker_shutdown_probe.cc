// Isolated diagnostic for worker creation before/after shutdown begins.
// Uses the same component libbase as Room, without starting a browser.
#include <cstdio>
#include <memory>
#include <pthread/qos.h>
#include <unistd.h>

#include "base/at_exit.h"
#include "base/check.h"
#include "base/command_line.h"
#include "base/feature_list.h"
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
}  // namespace

int main(int argc, char** argv) {
  alarm(15);
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::FeatureList::InitInstance("", "");
  CHECK(base::internal::CanUseBackgroundThreadTypeForWorkerThread());
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
