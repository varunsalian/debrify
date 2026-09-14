// Copyright (c) 2026 Debrify contributors. MIT license (see ../LICENSE).
#ifndef MEDIA_KIT_MAIN_THREAD_DISPATCHER_H_
#define MEDIA_KIT_MAIN_THREAD_DISPATCHER_H_

#include <functional>
#include <mutex>
#include <queue>
#include <utility>

// Shared by native workers independently of the plugin's lifetime. Drain and
// Close run on the platform thread; Post may run on any thread. The notifier
// must only post a window message, never synchronously execute queued work.
class MainThreadDispatcher {
 public:
  explicit MainThreadDispatcher(std::function<void()> notify)
      : notify_(std::move(notify)) {}

  void Post(std::function<void()> task) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (closed_) return;
    tasks_.push(std::move(task));
    // Serialize notification with Close so no worker posts to the old window
    // after the plugin has detached its window procedure.
    notify_();
  }

  void Drain() {
    for (;;) {
      std::function<void()> task;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (closed_ || tasks_.empty()) return;
        task = std::move(tasks_.front());
        tasks_.pop();
      }
      try {
        task();
      } catch (...) {
      }
    }
  }

  void Close() {
    std::queue<std::function<void()>> discarded;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      closed_ = true;
      tasks_.swap(discarded);
    }
    // Release captures outside the lock, while the plugin is still alive.
  }

 private:
  std::mutex mutex_;
  std::queue<std::function<void()>> tasks_;
  std::function<void()> notify_;
  bool closed_ = false;
};

#endif
