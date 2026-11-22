#include "desktop_window_chrome.h"

#include <commctrl.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>

namespace {

using Channel = flutter::MethodChannel<flutter::EncodableValue>;
constexpr UINT_PTR kChromeSubclass = 1;

const char* WindowState(HWND window) {
  return IsZoomed(window) ? "maximized" : "normal";
}

LRESULT CALLBACK ChromeProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto* channel = reinterpret_cast<Channel*>(data);
  switch (message) {
    case WM_NCCALCSIZE:
      if (wparam) {
        auto* layout = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const RECT proposed = layout->rgrc[0];
        DefSubclassProc(window, message, wparam, lparam);
        if (!IsZoomed(window)) {
          // Extend content into the caption while keeping resize borders.
          layout->rgrc[0].top = proposed.top;
        } else {
          MONITORINFO monitor = {};
          monitor.cbSize = sizeof(monitor);
          if (GetMonitorInfo(MonitorFromRect(&proposed, MONITOR_DEFAULTTONEAREST),
                             &monitor)) {
            layout->rgrc[0] = monitor.rcWork;
          }
        }
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return DefSubclassProc(window, message, wparam, -1);
    case WM_GETMINMAXINFO: {
      const auto result = DefSubclassProc(window, message, wparam, lparam);
      auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      const auto dpi = GetDpiForWindow(window);
      limits->ptMinTrackSize.x = std::max(limits->ptMinTrackSize.x,
                                         static_cast<LONG>(MulDiv(400, dpi, 96)));
      limits->ptMinTrackSize.y = std::max(limits->ptMinTrackSize.y,
                                         static_cast<LONG>(MulDiv(300, dpi, 96)));
      return result;
    }
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED) {
        channel->InvokeMethod("stateChanged",
            std::make_unique<flutter::EncodableValue>(WindowState(window)));
      }
      break;
    case WM_DESTROY:
      RemoveWindowSubclass(window, ChromeProc, id);
      channel->SetMethodCallHandler(nullptr);
      delete channel;
      break;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

}  // namespace

void RegisterDesktopWindowChrome(flutter::FlutterViewController* controller) {
  const HWND window = GetAncestor(controller->view()->GetNativeWindow(), GA_ROOT);
  auto channel = std::make_unique<Channel>(
      controller->engine()->messenger(), "dev.scrcpyconnect/desktop_window",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "state") {
      result->Success(flutter::EncodableValue(WindowState(window)));
      return;
    }
    if (method == "close") {
      PostMessage(window, WM_CLOSE, 0, 0);
    } else if (method == "minimize") {
      PostMessage(window, WM_SYSCOMMAND, SC_MINIMIZE, 0);
    } else if (method == "toggleMaximized") {
      PostMessage(window, WM_SYSCOMMAND, IsZoomed(window) ? SC_RESTORE : SC_MAXIMIZE, 0);
    } else if (method == "move" || method == "resize") {
      POINT pointer;
      GetCursorPos(&pointer);
      ReleaseCapture();
      PostMessage(window, WM_NCLBUTTONDOWN,
                  method == "move" ? HTCAPTION : HTTOP,
                  MAKELPARAM(pointer.x, pointer.y));
    } else {
      result->NotImplemented();
      return;
    }
    result->Success();
  });
  if (!SetWindowSubclass(window, ChromeProc, kChromeSubclass,
                         reinterpret_cast<DWORD_PTR>(channel.get()))) {
    channel->SetMethodCallHandler(nullptr);
    return;
  }
  channel.release();  // Owned by the HWND until WM_DESTROY.
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}
