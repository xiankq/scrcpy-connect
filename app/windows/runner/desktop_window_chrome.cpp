#include "desktop_window_chrome.h"

#include <commctrl.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <algorithm>
#include <memory>

namespace {

using Channel = flutter::MethodChannel<flutter::EncodableValue>;
using Value = flutter::EncodableValue;
constexpr UINT_PTR kChromeSubclass = 1;
constexpr UINT_PTR kContentSubclass = 2;

struct Chrome {
  HWND window;
  HWND content;
  bool title_bar;
  bool maximized;
  std::unique_ptr<Channel> channel;
};

// 顶边缩放命中带：系统缩放边框厚度。
int TopResizeBand(HWND window) {
  return GetSystemMetricsForDpi(SM_CYFRAME, GetDpiForWindow(window));
}

// 最大化时窗口越出显示器的边框厚度，客户区顶边需让出这部分。
int MaximizedOverhang(HWND window) {
  const UINT dpi = GetDpiForWindow(window);
  return GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

Value Layout(const Chrome& chrome) {
  return Value(flutter::EncodableMap{
      {Value("left"), Value(0.0)},
      {Value("right"), Value(0.0)},
      {Value("top"), Value(0.0)},
      {Value("titleBar"), Value(chrome.title_bar)},
      {Value("maximized"), Value(chrome.maximized)},
  });
}

void PublishMaximized(Chrome* chrome) {
  if (IsIconic(chrome->window)) return;
  const bool maximized = IsZoomed(chrome->window) != FALSE;
  if (maximized == chrome->maximized) return;
  chrome->maximized = maximized;
  chrome->channel->InvokeMethod("layoutChanged",
                                std::make_unique<Value>(Layout(*chrome)));
}

bool PrimaryButtonDown() {
  const int button = GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
  return (GetAsyncKeyState(button) & 0x8000) != 0;
}

// 交给系统移动循环，保留拖到屏幕边缘的贴靠。
void StartMove(const Chrome& chrome) {
  if (!PrimaryButtonDown()) return;
  ReleaseCapture();
  SendMessage(chrome.window, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
  // 移动循环吞掉了松开消息；补发给 Flutter 视图以结束这次按下。
  POINT cursor;
  if (GetCursorPos(&cursor) && ScreenToClient(chrome.content, &cursor)) {
    SendMessage(chrome.content, WM_LBUTTONUP, 0,
                MAKELPARAM(cursor.x, cursor.y));
  }
}

// Flutter 视图铺满客户区；顶边缩放带让给父窗口命中。
LRESULT CALLBACK ContentProc(HWND content, UINT message, WPARAM wparam,
                             LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  if (message == WM_NCHITTEST) {
    const HWND window = reinterpret_cast<HWND>(data);
    POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    if (!IsZoomed(window) && ScreenToClient(window, &point) &&
        point.y < TopResizeBand(window)) {
      return HTTRANSPARENT;
    }
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(content, ContentProc, id);
  }
  return DefSubclassProc(content, message, wparam, lparam);
}

LRESULT CALLBACK ChromeProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto* chrome = reinterpret_cast<Chrome*>(data);
  switch (message) {
    case WM_GETMINMAXINFO: {
      const auto result = DefSubclassProc(window, message, wparam, lparam);
      auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      const auto dpi = GetDpiForWindow(window);
      limits->ptMinTrackSize.x = std::max(
          limits->ptMinTrackSize.x, static_cast<LONG>(MulDiv(400, dpi, 96)));
      limits->ptMinTrackSize.y = std::max(
          limits->ptMinTrackSize.y, static_cast<LONG>(MulDiv(300, dpi, 96)));
      return result;
    }
    case WM_NCCALCSIZE: {
      if (!chrome->title_bar || !wparam) break;
      // 保留系统计算的左右下边框，去掉标题栏与顶边框。
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      const LONG top = params->rgrc[0].top;
      const auto result = DefSubclassProc(window, message, wparam, lparam);
      if (result != 0) return result;
      params->rgrc[0].top =
          top + (IsZoomed(window) ? MaximizedOverhang(window) : 0);
      return 0;
    }
    case WM_NCHITTEST: {
      if (!chrome->title_bar) break;
      const auto hit = DefSubclassProc(window, message, wparam, lparam);
      if (hit != HTCLIENT || IsZoomed(window)) return hit;
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      RECT client;
      if (!ScreenToClient(window, &point) || !GetClientRect(window, &client)) {
        return hit;
      }
      const int band = TopResizeBand(window);
      if (point.y >= band) return hit;
      if (point.x < band) return HTTOPLEFT;
      if (point.x >= client.right - band) return HTTOPRIGHT;
      return HTTOP;
    }
    case WM_SIZE: {
      const auto result = DefSubclassProc(window, message, wparam, lparam);
      PublishMaximized(chrome);
      return result;
    }
    case WM_DESTROY: {
      RemoveWindowSubclass(window, ChromeProc, id);
      std::unique_ptr<Chrome> owned(chrome);
      owned->channel->SetMethodCallHandler(nullptr);
      return DefSubclassProc(window, message, wparam, lparam);
    }
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

}  // namespace

void RegisterDesktopWindowChrome(flutter::FlutterViewController* controller,
                                 bool title_bar) {
  const HWND content = controller->view()->GetNativeWindow();
  const HWND window = GetAncestor(content, GA_ROOT);
  auto chrome = std::make_unique<Chrome>(Chrome{
      window, content, title_bar, IsZoomed(window) != FALSE,
      std::make_unique<Channel>(controller->engine()->messenger(),
                                "dev.scrcpyconnect/desktop_window",
                                &flutter::StandardMethodCodec::GetInstance())});
  if (!SetWindowSubclass(window, ChromeProc, kChromeSubclass,
                         reinterpret_cast<DWORD_PTR>(chrome.get()))) {
    return;
  }
  Chrome* state = chrome.release();  // Owned until WM_DESTROY.
  state->channel->SetMethodCallHandler([state](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "layout") {
      result->Success(Layout(*state));
    } else if (method == "activate") {
      if (IsIconic(state->window)) ShowWindow(state->window, SW_RESTORE);
      SetForegroundWindow(state->window);
      result->Success();
    } else if (method == "minimize") {
      PostMessage(state->window, WM_SYSCOMMAND, SC_MINIMIZE, 0);
      result->Success();
    } else if (method == "toggleMaximized") {
      PostMessage(state->window, WM_SYSCOMMAND,
                  IsZoomed(state->window) ? SC_RESTORE : SC_MAXIMIZE, 0);
      result->Success();
    } else if (method == "close") {
      PostMessage(state->window, WM_SYSCOMMAND, SC_CLOSE, 0);
      result->Success();
    } else if (method == "move") {
      result->Success();
      StartMove(*state);
    } else {
      result->NotImplemented();
    }
  });
  if (!title_bar) return;
  SetWindowSubclass(content, ContentProc, kContentSubclass,
                    reinterpret_cast<DWORD_PTR>(window));
  // 让新的非客户区生效，并把 Flutter 视图铺到扩大后的客户区。
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);
  RECT client;
  if (GetClientRect(window, &client)) {
    MoveWindow(content, 0, 0, client.right - client.left,
               client.bottom - client.top, TRUE);
  }
}
