#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// 支持高 DPI 的 Win32 窗口抽象，子类可定制渲染和输入处理。
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // 以指定标题、原点和尺寸在默认显示器创建窗口；系统使用物理像素，因此按默认显示器比例缩放以保持一致大小。调用 Show 前不可见，创建成功返回 true。
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // 显示当前窗口；成功返回 true。
  bool Show();

  // 释放窗口关联的系统资源。
  void Destroy();

  // 将内容插入窗口树。
  void SetChildContent(HWND content);

  // 返回窗口句柄以设置图标等属性；窗口已销毁时返回 nullptr。
  HWND GetHandle();

  // 设为 true 时关闭窗口同时退出应用。
  void SetQuitOnClose(bool quit_on_close);

  // 返回当前客户区边界 RECT。
  RECT GetClientArea();

 protected:
  // 处理并转发鼠标、尺寸和 DPI 消息，由子类覆写对应成员处理。
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // 创建窗口时调用，允许子类初始化；初始化失败应返回 false。
  virtual bool OnCreate();

  // 销毁窗口时调用。
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // 消息泵调用的系统回调；WM_NCCREATE 创建非客户区时启用自动 DPI 缩放，其余消息交由 MessageHandler。
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // 读取指定窗口关联的类实例指针。
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // 同步窗口边框与系统主题。
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // 顶层窗口句柄。
  HWND window_handle_ = nullptr;

  // 承载内容的子窗口句柄。
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
