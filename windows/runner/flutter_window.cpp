#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>
#include <windows.h>
#include <wincrypt.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
bool DecodeBase64(const std::string& source, std::vector<BYTE>* output) {
  DWORD size = 0;
  if (!CryptStringToBinaryA(source.c_str(), 0, CRYPT_STRING_BASE64, nullptr,
                            &size, nullptr, nullptr)) {
    return false;
  }
  output->resize(size);
  return CryptStringToBinaryA(source.c_str(), 0, CRYPT_STRING_BASE64,
                              output->data(), &size, nullptr, nullptr) != FALSE;
}

bool EncodeBase64(const BYTE* data, DWORD size, std::string* output) {
  DWORD chars = 0;
  if (!CryptBinaryToStringA(data, size,
                            CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                            nullptr, &chars)) {
    return false;
  }
  output->resize(chars);
  if (!CryptBinaryToStringA(data, size,
                            CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                            output->data(), &chars)) {
    return false;
  }
  if (!output->empty() && output->back() == '\0') output->pop_back();
  return true;
}

const std::string* StringArgument(const flutter::EncodableMap& args,
                                  const char* name) {
  auto found = args.find(flutter::EncodableValue(name));
  if (found == args.end()) return nullptr;
  return std::get_if<std::string>(&found->second);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  device_secret_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "debrify/device_secret",
          &flutter::StandardMethodCodec::GetInstance());
  device_secret_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "initialize") {
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "destroy") {
          // DPAPI uses the current Windows account and stores no Debrify key.
          result->Success();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        const char* payload_name =
            call.method_name() == "open" ? "envelope" : "plaintext";
        const std::string* payload = args ? StringArgument(*args, payload_name) : nullptr;
        const std::string* aad_text = args ? StringArgument(*args, "associatedData") : nullptr;
        if (!payload || !aad_text ||
            (call.method_name() != "seal" && call.method_name() != "open")) {
          result->Error("bad_args", "Invalid device-secret request");
          return;
        }
        std::vector<BYTE> input;
        std::vector<BYTE> aad;
        if (!DecodeBase64(*payload, &input) || !DecodeBase64(*aad_text, &aad)) {
          result->Error("bad_args", "Invalid base64 input");
          return;
        }
        DATA_BLOB input_blob{static_cast<DWORD>(input.size()), input.data()};
        DATA_BLOB entropy_blob{static_cast<DWORD>(aad.size()), aad.data()};
        DATA_BLOB output_blob{};
        const BOOL ok = call.method_name() == "seal"
            ? CryptProtectData(&input_blob, L"Debrify profile secret",
                               &entropy_blob, nullptr, nullptr,
                               CRYPTPROTECT_UI_FORBIDDEN, &output_blob)
            : CryptUnprotectData(&input_blob, nullptr, &entropy_blob, nullptr,
                                 nullptr, CRYPTPROTECT_UI_FORBIDDEN,
                                 &output_blob);
        if (!ok) {
          result->Error("device_secret_failed", "Windows DPAPI failed");
          return;
        }
        std::string encoded;
        const bool encoded_ok = EncodeBase64(output_blob.pbData,
                                             output_blob.cbData, &encoded);
        LocalFree(output_blob.pbData);
        if (!encoded_ok) {
          result->Error("device_secret_failed", "Could not encode result");
          return;
        }
        result->Success(flutter::EncodableValue(encoded));
      });
  profile_privacy_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.debrify.app/profile_privacy",
          &flutter::StandardMethodCodec::GetInstance());
  const HWND profile_window = GetHandle();
  profile_privacy_channel_->SetMethodCallHandler(
      [profile_window](const flutter::MethodCall<flutter::EncodableValue>& call,
                       std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setSensitive") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        bool sensitive = false;
        if (args) {
          const auto found = args->find(flutter::EncodableValue("sensitive"));
          if (found != args->end()) {
            if (const auto* value = std::get_if<bool>(&found->second)) sensitive = *value;
          }
        }
        const DWORD affinity = sensitive ? 0x00000011 /* WDA_EXCLUDEFROMCAPTURE */
                                         : WDA_NONE;
        if (!SetWindowDisplayAffinity(profile_window, affinity)) {
          result->Error("privacy_failed", "Could not update capture protection");
          return;
        }
        result->Success(flutter::EncodableValue(true));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    profile_privacy_channel_.reset();
    device_secret_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
