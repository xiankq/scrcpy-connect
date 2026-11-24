#include "desktop_window_chrome.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>

namespace {

using Channel = flutter::MethodChannel<flutter::EncodableValue>;
using Value = flutter::EncodableValue;
constexpr UINT_PTR kChromeSubclass = 1;
constexpr int kCompactWidth = 600;

struct CaptionInsets {
  double right = 0;
  double top = 0;

  Value Encode() const {
    return Value(flutter::EncodableMap{
        {Value("left"), Value(0.0)},
        {Value("right"), Value(right)},
        {Value("top"), Value(top)},
    });
  }
};

struct Chrome {
  std::unique_ptr<Channel> channel;
  bool immersive;
  CaptionInsets last_layout;
};

int TopResizeBorder(HWND window) {
  const auto dpi = GetDpiForWindow(window);
  return GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

bool IsWide(HWND window) {
  RECT client = {};
  GetClientRect(window, &client);
  return client.right >= MulDiv(kCompactWidth, GetDpiForWindow(window), 96);
}

void ExtendFrame(HWND window, bool immersive) {
  const int height = GetSystemMetricsForDpi(SM_CYCAPTION, GetDpiForWindow(window));
  const MARGINS margins = {0, 0, immersive ? height + TopResizeBorder(window) : 0, 0};
  DwmExtendFrameIntoClientArea(window, &margins);
}

CaptionInsets Layout(HWND window, bool immersive) {
  if (!immersive) return {};
  const auto dpi = GetDpiForWindow(window);
  double right = 3 * GetSystemMetricsForDpi(SM_CXSIZE, dpi);
  double top = GetSystemMetricsForDpi(SM_CYCAPTION, dpi) +
               TopResizeBorder(window);
  RECT buttons = {}, frame = {}, client = {};
  POINT origin = {};
  if (IsWindowVisible(window) && !IsIconic(window) &&
      SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CAPTION_BUTTON_BOUNDS,
                                      &buttons, sizeof(buttons))) &&
      !IsRectEmpty(&buttons)) {
    GetWindowRect(window, &frame);
    GetClientRect(window, &client);
    ClientToScreen(window, &origin);
    right = std::max(0L, origin.x + client.right - (frame.left + buttons.left));
    top = std::max(0L, frame.top + buttons.bottom - origin.y);
  }
  const double scale = dpi / 96.0;
  return {right / scale, top / scale};
}

// The Flutter surface is a child HWND. Route system caption and top-edge
// hits to its owner so DWM can hover and operate its own buttons.
LRESULT CALLBACK SurfaceProc(HWND surface, UINT message, WPARAM wparam,
                             LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  if (message == WM_NCHITTEST) {
    const HWND window = reinterpret_cast<HWND>(data);
    const auto hit = SendMessage(window, message, wparam, lparam);
    if (hit == HTMINBUTTON || hit == HTMAXBUTTON || hit == HTCLOSE ||
        hit == HTTOP || hit == HTTOPLEFT || hit == HTTOPRIGHT) {
      return HTTRANSPARENT;
    }
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(surface, SurfaceProc, id);
  }
  return DefSubclassProc(surface, message, wparam, lparam);
}

LRESULT CALLBACK ChromeProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto* chrome = reinterpret_cast<Chrome*>(data);
  LRESULT system_result = 0;
  if (DwmDefWindowProc(window, message, wparam, lparam, &system_result)) {
    return system_result;
  }
  switch (message) {
    case WM_NCCALCSIZE:
      if (chrome->immersive && wparam) {
        auto* layout = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const RECT proposed = layout->rgrc[0];
        DefSubclassProc(window, message, wparam, lparam);
        if (!IsZoomed(window)) {
          // Keep the resize borders while extending the client to the top.
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
    case WM_NCHITTEST:
      if (chrome->immersive && !IsZoomed(window)) {
        RECT frame = {};
        GetWindowRect(window, &frame);
        const int border = TopResizeBorder(window);
        if (GET_Y_LPARAM(lparam) - frame.top < border) {
          const int x = GET_X_LPARAM(lparam);
          if (x - frame.left < border) return HTTOPLEFT;
          if (frame.right - x <= border) return HTTOPRIGHT;
          return HTTOP;
        }
      }
      break;
    case WM_NCACTIVATE:
      if (chrome->immersive) {
        return DefSubclassProc(window, message, wparam, -1);
      }
      break;
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
    case WM_ACTIVATE:
    case WM_DWMCOMPOSITIONCHANGED:
    case WM_DPICHANGED:
      ExtendFrame(window, chrome->immersive);
      [[fallthrough]];
    case WM_SIZE:
      if (!IsIconic(window)) {
        const bool immersive = IsWide(window);
        if (immersive != chrome->immersive) {
          chrome->immersive = immersive;
          ExtendFrame(window, immersive);
          SetWindowPos(window, nullptr, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                           SWP_FRAMECHANGED);
        }
        const auto layout = Layout(window, chrome->immersive);
        if (layout.right != chrome->last_layout.right ||
            layout.top != chrome->last_layout.top) {
          chrome->last_layout = layout;
          chrome->channel->InvokeMethod("layoutChanged",
                                        std::make_unique<Value>(layout.Encode()));
        }
      }
      break;
    case WM_DESTROY:
      RemoveWindowSubclass(window, ChromeProc, id);
      chrome->channel->SetMethodCallHandler(nullptr);
      delete chrome;
      break;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

}  // namespace

void RegisterDesktopWindowChrome(flutter::FlutterViewController* controller) {
  const HWND surface = controller->view()->GetNativeWindow();
  const HWND window = GetAncestor(surface, GA_ROOT);
  auto chrome = std::make_unique<Chrome>(Chrome{
      std::make_unique<Channel>(controller->engine()->messenger(),
                               "dev.scrcpyconnect/desktop_window",
                               &flutter::StandardMethodCodec::GetInstance()),
      IsWide(window), {}});
  chrome->channel->SetMethodCallHandler([window, state = chrome.get()](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "layout") {
      result->Success(Layout(window, state->immersive).Encode());
      return;
    }
    if (method == "activate") {
      if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
      SetForegroundWindow(window);
    } else if (method == "toggleMaximized") {
      PostMessage(window, WM_SYSCOMMAND,
                  IsZoomed(window) ? SC_RESTORE : SC_MAXIMIZE, 0);
    } else if (method == "move") {
      POINT pointer;
      GetCursorPos(&pointer);
      ReleaseCapture();
      PostMessage(window, WM_NCLBUTTONDOWN, HTCAPTION,
                  MAKELPARAM(pointer.x, pointer.y));
    } else {
      result->NotImplemented();
      return;
    }
    result->Success();
  });
  if (!SetWindowSubclass(window, ChromeProc, kChromeSubclass,
                         reinterpret_cast<DWORD_PTR>(chrome.get()))) {
    chrome->channel->SetMethodCallHandler(nullptr);
    return;
  }
  if (surface != window) {
    SetWindowSubclass(surface, SurfaceProc, kChromeSubclass,
                     reinterpret_cast<DWORD_PTR>(window));
  }
  const bool immersive = chrome.release()->immersive;  // Owned until WM_DESTROY.
  ExtendFrame(window, immersive);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}
