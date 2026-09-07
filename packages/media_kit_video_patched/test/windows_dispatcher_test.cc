#include <atomic>
#include <cassert>
#include <future>
#include <memory>
#include <thread>

#include "main_thread_dispatcher.h"

struct Plugin {
  std::shared_ptr<MainThreadDispatcher> dispatcher;
  int replies = 0;
  explicit Plugin(std::atomic<int>& notifications)
      : dispatcher(std::make_shared<MainThreadDispatcher>(
            [&notifications] { ++notifications; })) {}
  ~Plugin() { dispatcher->Close(); }
};

int main() {
  std::atomic<int> notifications{0};
  auto plugin = std::make_unique<Plugin>(notifications);
  auto dispatcher = plugin->dispatcher;
  auto owner = plugin.get();

  // Normal replies execute only when the platform thread drains the queue.
  std::thread normal([dispatcher, owner] {
    dispatcher->Post([owner] { ++owner->replies; });
  });
  normal.join();
  assert(plugin->replies == 0);
  dispatcher->Drain();
  assert(plugin->replies == 1);

  // Already queued tasks must be discarded when the plugin goes away.
  auto retained = std::make_shared<int>(1);
  std::weak_ptr<int> weak = retained;
  dispatcher->Post([owner, retained] { ++owner->replies; });
  retained.reset();

  // Reproduce completion arriving after the plugin has been destroyed. The
  // worker owns the dispatcher, and never dereferences the plugin itself.
  std::promise<void> resume;
  auto ready = resume.get_future();
  std::thread late([dispatcher, owner, ready = std::move(ready)]() mutable {
    ready.wait();
    dispatcher->Post([owner] { ++owner->replies; });
  });
  plugin.reset();
  assert(weak.expired());
  auto before = notifications.load();
  resume.set_value();
  late.join();
  dispatcher->Drain();
  assert(notifications == before);

  // A task can tear down its owner while Drain is running. Subsequent work
  // must not execute, and the dispatcher remains alive for Drain's return.
  plugin = std::make_unique<Plugin>(notifications);
  dispatcher = plugin->dispatcher;
  dispatcher->Post([&plugin] { plugin.reset(); });
  dispatcher->Post([] { assert(false); });
  dispatcher->Drain();

  // Exercise Post/Close contention, including posts after Close returns.
  for (int i = 0; i < 100; ++i) {
    dispatcher = std::make_shared<MainThreadDispatcher>([&] { ++notifications; });
    std::thread producer([dispatcher] {
      for (int n = 0; n < 100; ++n) dispatcher->Post([] { assert(false); });
    });
    dispatcher->Close();
    before = notifications.load();
    producer.join();
    dispatcher->Drain();
    assert(notifications == before);
  }
}
