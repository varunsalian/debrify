"""Run the production Windows teardown bodies with controlled native fakes.

Requires Python 3 and a C++17 compiler. Does not replace a Windows playback test.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = (root / 'windows/video_output.cc').read_text()
manager = (root / 'windows/video_output_manager.cc').read_text()
destructor = output[output.index('VideoOutput::~VideoOutput() {'):output.index('\nvoid VideoOutput::NotifyRender()')]
dispose = manager[manager.index('void VideoOutputManager::Dispose('):]
source = r'''
#include <atomic>
#include <cassert>
#include <chrono>
#include <functional>
#include <future>
#include <memory>
#include <thread>
#include <unordered_map>
#include "thread_pool.h"
using namespace std::chrono_literals;
struct Context {
  std::promise<void> entered, allow;
  std::atomic<bool> freed{false}, detached{false}, current{false};
  bool hardware = false;
};
void mpv_render_context_set_update_callback(Context* c, void*, void*) {
  c->detached = true;
}
void mpv_render_context_free(Context* c) {
  assert(c->detached);
  assert(!c->hardware || c->current);
  c->entered.set_value();
  c->allow.get_future().wait();
  c->freed = true;
}
struct Surface {
  Context* context;
  void MakeCurrent(bool value) { context->current = value; }
  ~Surface() { assert(context->freed); }
};
struct Registrar {
  std::promise<void> requested, allow;
  std::thread callback;
  Registrar* texture_registrar() { return this; }
  void UnregisterTexture(int64_t, std::function<void()> done) {
    callback = std::thread([this, done] {
      requested.set_value();
      allow.get_future().wait();
      done();
    });
  }
  ~Registrar() { if (callback.joinable()) callback.join(); }
};
struct VideoOutput {
  std::atomic<bool> destroyed_{false};
  Context* render_context_;
  ThreadPool* thread_pool_ref_;
  Registrar* registrar_;
  int64_t texture_id_;
  std::mutex textures_mutex_;
  std::unordered_map<int, int> texture_variants_, textures_, pixel_buffer_textures_;
  std::unique_ptr<Surface> surface_manager_;
  VideoOutput(Context* c, ThreadPool* p, Registrar* r, bool texture, bool hardware)
      : render_context_(c), thread_pool_ref_(p), registrar_(r), texture_id_(texture) {
    if (hardware) surface_manager_ = std::make_unique<Surface>(Surface{c});
  }
  ~VideoOutput();
};
struct VideoOutputManager {
  std::mutex mutex_;
  std::unordered_map<int64_t, std::unique_ptr<VideoOutput>> video_outputs_;
  ThreadPool operations_{1};
  void Dispose(int64_t, std::function<void()>);
  ~VideoOutputManager();
};
'''
# Avoid a temporary Surface whose destructor would run before cleanup.
source = source.replace('std::make_unique<Surface>(Surface{c})', 'std::unique_ptr<Surface>(new Surface{c})')
source += destructor + '\n' + dispose
source += r'''
void exercise(bool texture, bool hardware, bool context) {
  ThreadPool pool(1);
  Context native;
  native.hardware = hardware;
  Registrar registrar;
  VideoOutputManager manager;
  manager.video_outputs_[1] = std::make_unique<VideoOutput>(
      context ? &native : nullptr, &pool, &registrar, texture, hardware);
  std::promise<void> done, duplicate;
  auto finished = done.get_future();
  auto twice = duplicate.get_future();
  manager.Dispose(1, [&] { done.set_value(); });
  if (texture) {
    assert(registrar.requested.get_future().wait_for(2s) == std::future_status::ready);
    assert(finished.wait_for(20ms) == std::future_status::timeout);
    registrar.allow.set_value();
  }
  if (context) {
    assert(native.entered.get_future().wait_for(2s) == std::future_status::ready);
    manager.Dispose(1, [&] { duplicate.set_value(); });
    assert(finished.wait_for(20ms) == std::future_status::timeout);
    assert(twice.wait_for(20ms) == std::future_status::timeout);
    native.allow.set_value();
    assert(twice.wait_for(2s) == std::future_status::ready);
  }
  assert(finished.wait_for(2s) == std::future_status::ready);
  assert(!context || native.freed);
  std::promise<void> missing;
  auto absent = missing.get_future();
  manager.Dispose(999, [&] { missing.set_value(); });
  assert(absent.wait_for(2s) == std::future_status::ready);
}
void delayed_worker_shutdown() {
  auto manager = std::make_unique<VideoOutputManager>();
  std::promise<void> entered, release;
  auto resume = release.get_future();
  manager->operations_.Post([&] {
    entered.set_value();
    resume.wait();
  });
  entered.get_future().wait();
  std::atomic<bool> replied{false};
  manager->Dispose(1, [&] { replied = true; });
  auto shutdown = std::async(std::launch::async, [&] { manager.reset(); });
  assert(shutdown.wait_for(20ms) == std::future_status::timeout);
  assert(!replied);
  release.set_value();
  assert(shutdown.wait_for(2s) == std::future_status::ready);
  shutdown.get();
  assert(replied);
}

void active_output_shutdown() {
  ThreadPool render(1);
  Context native;
  Registrar registrar;
  auto manager = std::make_unique<VideoOutputManager>();
  manager->video_outputs_[1] = std::make_unique<VideoOutput>(
      &native, &render, &registrar, true, false);
  auto shutdown = std::async(std::launch::async, [&] { manager.reset(); });
  assert(registrar.requested.get_future().wait_for(2s) == std::future_status::ready);
  assert(shutdown.wait_for(20ms) == std::future_status::timeout);
  registrar.allow.set_value();
  assert(native.entered.get_future().wait_for(2s) == std::future_status::ready);
  assert(shutdown.wait_for(20ms) == std::future_status::timeout);
  native.allow.set_value();
  assert(shutdown.wait_for(2s) == std::future_status::ready);
  shutdown.get();
  assert(native.freed);
}

int main() {
  delayed_worker_shutdown();
  active_output_shutdown();
  exercise(true, true, true);
  exercise(true, false, true);
  exercise(false, false, true);
  exercise(false, false, false);
}
'''
with tempfile.TemporaryDirectory() as tmp:
    cpp = Path(tmp) / 'test.cc'
    exe = Path(tmp) / 'test'
    cpp.write_text(source)
    subprocess.run([os.environ.get('CXX', 'c++'), '-std=c++17', '-pthread',
                    '-Wall', '-Wextra', '-Werror', '-fsanitize=address', '-g',
                    '-I', str(root / 'windows'),
                    str(cpp), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=15)
print('PASS (AddressSanitizer): delayed manager worker and active-output shutdown; hardware/software disposal, duplicate/missing handles')

with tempfile.TemporaryDirectory() as tmp:
    exe = Path(tmp) / 'dispatcher_test'
    subprocess.run([os.environ.get('CXX', 'c++'), '-std=c++17', '-pthread',
                    '-Wall', '-Wextra', '-Werror', '-fsanitize=address', '-g',
                    '-I', str(root / 'windows'),
                    str(root / 'test/windows_dispatcher_test.cc'),
                    '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=15)
print('PASS (AddressSanitizer): plugin teardown, late/queued completions, reentrant close, concurrent posting')
