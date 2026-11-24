#include "desktop_window_chrome.h"

#include <commctrl.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>

namespace {

using Channel = flutter::MethodChannel<flutter::EncodableValue>;
using Value = flutter::EncodableValue;
constexpr UINT_PTR kChromeSubclass = 1;

LRESULT CALLBACK ChromeProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  if (message == WM_GETMINMAXINFO) {
    const auto result = DefSubclassProc(window, message, wparam, lparam);
    auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
    const auto dpi = GetDpiForWindow(window);
    limits->ptMinTrackSize.x = std::max(limits->ptMinTrackSize.x,
                                       static_cast<LONG>(MulDiv(400, dpi, 96)));
    limits->ptMinTrackSize.y = std::max(limits->ptMinTrackSize.y,
                                       static_cast<LONG>(MulDiv(300, dpi, 96)));
    return result;
  }
  if (message == WM_DESTROY) {
    RemoveWindowSubclass(window, ChromeProc, id);
    std::unique_ptr<Channel> channel(reinterpret_cast<Channel*>(data));
    channel->SetMethodCallHandler(nullptr);
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

}  // namespace

void RegisterDesktopWindowChrome(flutter::FlutterViewController* controller) {
  const HWND window = GetAncestor(controller->view()->GetNativeWindow(), GA_ROOT);
  auto channel = std::make_unique<Channel>(
      controller->engine()->messenger(), "dev.scrcpyconnect/desktop_window",
      &flutter::StandardMethodCodec::GetInstance());
  if (!SetWindowSubclass(window, ChromeProc, kChromeSubclass,
                         reinterpret_cast<DWORD_PTR>(channel.get()))) {
    return;
  }
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    if (call.method_name() == "layout") {
      result->Success(Value(flutter::EncodableMap{
          {Value("left"), Value(0.0)},
          {Value("right"), Value(0.0)},
          {Value("top"), Value(0.0)},
      }));
    } else if (call.method_name() == "activate") {
      if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
      SetForegroundWindow(window);
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  channel.release();  // Owned until WM_DESTROY.
}
