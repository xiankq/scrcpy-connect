#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

class SystemTypography;

// 仅承载 Flutter 视图的窗口。
class FlutterWindow : public Win32Window {
 public:
  // 创建运行指定 project 的 Flutter 视图窗口。
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // 继承自 Win32Window 的生命周期回调。
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // 要运行的项目。
  flutter::DartProject project_;

  // 此窗口承载的 Flutter 实例。
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<SystemTypography> system_typography_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
