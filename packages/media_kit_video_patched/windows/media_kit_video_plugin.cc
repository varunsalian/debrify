// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.
#include "media_kit_video_plugin.h"
#include "utils.h"

#include <Windows.h>

namespace media_kit_video {

MediaKitVideoPlugin* MediaKitVideoPlugin::instance_ = nullptr;

void MediaKitVideoPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<MediaKitVideoPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

MediaKitVideoPlugin::MediaKitVideoPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      video_output_manager_(std::make_unique<VideoOutputManager>(registrar)) {
  instance_ = this;
  flutter_window_ =
      ::GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
  original_window_proc_ = reinterpret_cast<WNDPROC>(
      ::SetWindowLongPtr(flutter_window_, GWLP_WNDPROC,
                         reinterpret_cast<LONG_PTR>(WindowProcDelegate)));

  main_thread_dispatcher_ = std::make_shared<MainThreadDispatcher>(
      [window = flutter_window_]() {
        ::PostMessage(window, kMainThreadTaskMessage, 0, 0);
      });

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "com.alexmercerind/media_kit_video",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([&](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

MediaKitVideoPlugin::~MediaKitVideoPlugin() {
  main_thread_dispatcher_->Close();
  if (flutter_window_ && original_window_proc_) {
    ::SetWindowLongPtr(flutter_window_, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(original_window_proc_));
  }
  if (instance_ == this) {
    instance_ = nullptr;
  }
}

LRESULT CALLBACK MediaKitVideoPlugin::WindowProcDelegate(HWND hwnd,
                                                         UINT message,
                                                         WPARAM wParam,
                                                         LPARAM lParam) {
  if (message == kMainThreadTaskMessage && instance_) {
    instance_->ProcessMainThreadTasks();
    return 0;
  }

  if (instance_ && instance_->original_window_proc_) {
    return ::CallWindowProc(instance_->original_window_proc_, hwnd, message,
                            wParam, lParam);
  }

  return ::DefWindowProc(hwnd, message, wParam, lParam);
}

void MediaKitVideoPlugin::ProcessMainThreadTasks() {
  // Keep the dispatcher alive if executing a task triggers plugin teardown.
  auto dispatcher = main_thread_dispatcher_;
  dispatcher->Drain();
}

void MediaKitVideoPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("VideoOutputManager.Create") == 0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto configuration = std::get<flutter::EncodableMap>(
        arguments[flutter::EncodableValue("configuration")]);

    auto handle_value = std::stoll(handle);
    auto configuration_value = VideoOutputConfiguration{};

    auto configuration_width =
        std::get<std::string>(configuration[flutter::EncodableValue("width")]);
    auto configuration_height =
        std::get<std::string>(configuration[flutter::EncodableValue("height")]);
    auto configuration_enable_hardware_acceleration = std::get<bool>(
        configuration[flutter::EncodableValue("enableHardwareAcceleration")]);
    if (configuration_width.compare("null") != 0) {
      configuration_value.width =
          static_cast<int64_t>(std::stoll(configuration_width.c_str()));
    }
    if (configuration_height.compare("null") != 0) {
      configuration_value.height =
          static_cast<int64_t>(std::stoll(configuration_height.c_str()));
    }
    configuration_value.enable_hardware_acceleration =
        configuration_enable_hardware_acceleration;

    video_output_manager_->Create(
        handle_value, configuration_value,
        [this, dispatcher = main_thread_dispatcher_, handle = handle_value](
            auto id, auto width, auto height) {
          dispatcher->Post([=]() {
            channel_->InvokeMethod(
                "VideoOutput.Resize",
                std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                    {
                        flutter::EncodableValue("handle"),
                        flutter::EncodableValue(handle),
                    },
                    {
                        flutter::EncodableValue("id"),
                        flutter::EncodableValue(id),
                    },
                    {
                        flutter::EncodableValue("rect"),
                        flutter::EncodableValue(flutter::EncodableMap{
                            {
                                flutter::EncodableValue("left"),
                                flutter::EncodableValue(0),
                            },
                            {
                                flutter::EncodableValue("top"),
                                flutter::EncodableValue(0),
                            },
                            {
                                flutter::EncodableValue("width"),
                                flutter::EncodableValue(width),
                            },
                            {
                                flutter::EncodableValue("height"),
                                flutter::EncodableValue(height),
                            },
                        }),
                    },
                }),
                nullptr);
          });
        });
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("VideoOutputManager.Dispose") ==
             0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto handle_value = static_cast<int64_t>(std::stoll(handle.c_str()));
    auto pending_result =
        std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
    video_output_manager_->Dispose(
        handle_value, [dispatcher = main_thread_dispatcher_, pending_result]() {
          dispatcher->Post([pending_result]() {
            pending_result->Success(flutter::EncodableValue(std::monostate{}));
          });
        });
  } else if (method_call.method_name().compare("VideoOutputManager.SetSize") ==
             0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto width =
        std::get<std::string>(arguments[flutter::EncodableValue("width")]);
    auto height =
        std::get<std::string>(arguments[flutter::EncodableValue("height")]);
    auto handle_value = static_cast<int64_t>(std::stoll(handle.c_str()));
    auto width_value = std::optional<int64_t>{};
    auto height_value = std::optional<int64_t>{};
    if (width.compare("null") != 0) {
      width_value = static_cast<int64_t>(std::stoll(width.c_str()));
    }
    if (height.compare("null") != 0) {
      height_value = static_cast<int64_t>(std::stoll(height.c_str()));
    }
    video_output_manager_->SetSize(handle_value, width_value, height_value);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("Utils.EnterNativeFullscreen") ==
             0) {
    auto window =
        ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
    Utils::EnterNativeFullscreen(window);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("Utils.ExitNativeFullscreen") ==
             0) {
    auto window =
        ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
    Utils::ExitNativeFullscreen(window);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else {
    result->NotImplemented();
  }
}

}  // namespace media_kit_video
