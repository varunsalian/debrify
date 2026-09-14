// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "video_output_manager.h"

VideoOutputManager::VideoOutputManager(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

void VideoOutputManager::Create(
    int64_t handle,
    VideoOutputConfiguration configuration,
    std::function<void(int64_t, int64_t, int64_t)> texture_update_callback) {
  operations_.Post([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) == video_outputs_.end()) {
      auto instance = std::make_unique<VideoOutput>(
          handle, configuration, registrar_, thread_pool_.get());
      instance->SetTextureUpdateCallback(texture_update_callback);
      video_outputs_.insert(std::make_pair(handle, std::move(instance)));
    }
  });
}

void VideoOutputManager::SetSize(int64_t handle,
                                 std::optional<int64_t> width,
                                 std::optional<int64_t> height) {
  operations_.Post([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) != video_outputs_.end()) {
      video_outputs_[handle]->SetSize(width, height);
    }
  });
}

void VideoOutputManager::Dispose(int64_t handle,
                                 std::function<void()> completion) {
  operations_.Post([=]() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (video_outputs_.find(handle) != video_outputs_.end()) {
        video_outputs_.erase(handle);
      }
    }
    // The lock also makes duplicate Dispose calls wait for the first teardown.
    completion();
  });
}

VideoOutputManager::~VideoOutputManager() {
  // FIFO shutdown runs after every accepted operation. Keep the manager,
  // registrar and render worker alive until all output teardown has finished.
  operations_.Post([this]() { video_outputs_.clear(); }).wait();
  // operations_ is destroyed first and joins its worker before other members.
}
