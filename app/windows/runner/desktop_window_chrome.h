#ifndef RUNNER_DESKTOP_WINDOW_CHROME_H_
#define RUNNER_DESKTOP_WINDOW_CHROME_H_

#include <flutter/flutter_view_controller.h>

// 注册 dev.scrcpyconnect/desktop_window。title_bar 为 true 时隐去系统标题栏，
// 保留左右下缩放边框与 DWM 阴影，由 Flutter 绘制标题栏；只用于主窗口。
void RegisterDesktopWindowChrome(flutter::FlutterViewController* controller,
                                 bool title_bar);

#endif  // RUNNER_DESKTOP_WINDOW_CHROME_H_
