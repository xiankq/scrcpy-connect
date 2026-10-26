#include "flutter_window.h"

#include <optional>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

class SystemTypography {
 public:
  explicit SystemTypography(flutter::BinaryMessenger* messenger)
      : methods_(messenger, "dev.scrcpyconnect/system_typography",
                 &flutter::StandardMethodCodec::GetInstance()),
        events_(messenger, "dev.scrcpyconnect/system_typography/events",
                &flutter::StandardMethodCodec::GetInstance()) {
    methods_.SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
          if (call.method_name() != "read") {
            result->NotImplemented();
            return;
          }
          auto snapshot = Snapshot();
          if (snapshot) {
            result->Success(*snapshot);
          } else {
            result->Error("unavailable", "System font is unavailable");
          }
        });
    events_.SetStreamHandler(
        std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
            [this](const flutter::EncodableValue*,
                   std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink)
                -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
              sink_ = std::move(sink);
              Publish();
              return nullptr;
            },
            [this](const flutter::EncodableValue*)
                -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
              sink_.reset();
              return nullptr;
            }));
  }

  ~SystemTypography() {
    sink_.reset();
    events_.SetStreamHandler(nullptr);
    methods_.SetMethodCallHandler(nullptr);
  }

  void Publish() {
    if (!sink_) return;
    auto snapshot = Snapshot();
    if (snapshot) sink_->Success(*snapshot);
  }

 private:
  std::optional<flutter::EncodableValue> Snapshot() {
    NONCLIENTMETRICSW metrics = {};
    metrics.cbSize = sizeof(metrics);
    if (!SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics), &metrics,
                               0)) {
      return std::nullopt;
    }
    const std::string family = Utf8FromUtf16(metrics.lfMessageFont.lfFaceName);
    if (family.empty()) return std::nullopt;
    return flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("revision"), flutter::EncodableValue(++revision_)},
        {flutter::EncodableValue("fontFamily"), flutter::EncodableValue(family)}});
  }

  flutter::MethodChannel<flutter::EncodableValue> methods_;
  flutter::EventChannel<flutter::EncodableValue> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  int64_t revision_ = 0;
};

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // 此处大小必须与窗口尺寸一致，避免启动时反复创建和销毁渲染表面。
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // 确认控制器基础设置成功。
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  system_typography_ = std::make_unique<SystemTypography>(
      flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter 首帧可能早于显示窗口回调注册；主动安排一帧以确保窗口可见，首帧尚未完成时此调用不产生额外效果。
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  system_typography_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 先读取真实字族；引擎处理这些消息时可能直接返回。
  if (flutter_controller_ &&
      (message == WM_SETTINGCHANGE || message == WM_FONTCHANGE)) {
    flutter_controller_->engine()->ReloadSystemFonts();
    if (system_typography_) system_typography_->Publish();
  }
  // 先让 Flutter 及插件处理窗口消息。
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
