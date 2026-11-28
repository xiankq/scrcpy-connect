#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"
#include <desktop_multi_window/desktop_multi_window_plugin.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

namespace {

struct SystemTypography {
  GtkSettings* settings;
  FlMethodChannel* methods;
  FlEventChannel* events;
  gulong font_changed;
  gint64 revision = 0;
  bool listening = false;
};

FlValue* typography_snapshot(SystemTypography* self) {
  g_autofree gchar* name = nullptr;
  g_object_get(self->settings, "gtk-font-name", &name, nullptr);
  if (name == nullptr || *name == '\0') return nullptr;
  PangoFontDescription* description = pango_font_description_from_string(name);
  const gchar* family = pango_font_description_get_family(description);
  FlValue* snapshot = nullptr;
  if (family != nullptr && *family != '\0') {
    snapshot = fl_value_new_map();
    fl_value_set_string_take(snapshot, "revision",
                             fl_value_new_int(++self->revision));
    fl_value_set_string_take(snapshot, "fontFamily", fl_value_new_string(family));
  }
  pango_font_description_free(description);
  return snapshot;
}

void typography_publish(SystemTypography* self) {
  if (!self->listening) return;
  g_autoptr(FlValue) snapshot = typography_snapshot(self);
  if (snapshot != nullptr) {
    fl_event_channel_send(self->events, snapshot, nullptr, nullptr);
  }
}

void typography_read(FlMethodChannel* channel, FlMethodCall* call,
                     gpointer user_data) {
  auto* self = static_cast<SystemTypography*>(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(fl_method_call_get_name(call), "read") != 0) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else {
    g_autoptr(FlValue) snapshot = typography_snapshot(self);
    response = snapshot != nullptr
                   ? FL_METHOD_RESPONSE(fl_method_success_response_new(snapshot))
                   : FL_METHOD_RESPONSE(fl_method_error_response_new(
                         "unavailable", "System font is unavailable", nullptr));
  }
  fl_method_call_respond(call, response, nullptr);
}

FlMethodErrorResponse* typography_listen(FlEventChannel* channel, FlValue* args,
                                        gpointer user_data) {
  auto* self = static_cast<SystemTypography*>(user_data);
  self->listening = true;
  typography_publish(self);
  return nullptr;
}

FlMethodErrorResponse* typography_cancel(FlEventChannel* channel, FlValue* args,
                                        gpointer user_data) {
  static_cast<SystemTypography*>(user_data)->listening = false;
  return nullptr;
}

void typography_dispose(gpointer data) {
  auto* self = static_cast<SystemTypography*>(data);
  self->listening = false;
  g_signal_handler_disconnect(self->settings, self->font_changed);
  fl_event_channel_set_stream_handlers(self->events, nullptr, nullptr, nullptr,
                                       nullptr);
  fl_method_channel_set_method_call_handler(self->methods, nullptr, nullptr,
                                            nullptr);
  g_object_unref(self->events);
  g_object_unref(self->methods);
  g_object_unref(self->settings);
  delete self;
}

void register_system_typography(FlView* view) {
  auto* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* self = new SystemTypography{
      GTK_SETTINGS(g_object_ref(gtk_widget_get_settings(GTK_WIDGET(view)))),
      fl_method_channel_new(messenger, "dev.scrcpyconnect/system_typography",
                             FL_METHOD_CODEC(codec)),
      fl_event_channel_new(messenger,
                            "dev.scrcpyconnect/system_typography/events",
                            FL_METHOD_CODEC(codec)),
      0};
  fl_method_channel_set_method_call_handler(self->methods, typography_read, self,
                                            nullptr);
  fl_event_channel_set_stream_handlers(self->events, typography_listen,
                                       typography_cancel, self, nullptr);
  self->font_changed = g_signal_connect(
      self->settings, "notify::gtk-font-name",
      G_CALLBACK(+[](GObject*, GParamSpec*, gpointer data) {
        typography_publish(static_cast<SystemTypography*>(data));
      }),
      self);
  g_object_set_data_full(G_OBJECT(view), "system-typography", self,
                         typography_dispose);
  g_signal_connect(
      view, "destroy", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
        // 在视图释放引擎之前注销 messenger 与 GTK 回调。
        g_object_set_data(G_OBJECT(widget), "system-typography", nullptr);
      }),
      nullptr);
}

struct DesktopWindow {
  GtkWindow* window;
  FlMethodChannel* channel;
  bool title_bar;
  bool maximized;
  gulong state_changed;
  gulong press_hook;
  // 最近一次在本窗口按下的事件；拖动窗口时交给窗口管理器。
  GdkEvent* press;
  GtkWidget* press_widget;
};

FlValue* desktop_window_layout(DesktopWindow* self) {
  FlValue* layout = fl_value_new_map();
  fl_value_set_string_take(layout, "left", fl_value_new_int(0));
  fl_value_set_string_take(layout, "right", fl_value_new_int(0));
  fl_value_set_string_take(layout, "top", fl_value_new_int(0));
  fl_value_set_string_take(layout, "titleBar",
                           fl_value_new_bool(self->title_bar));
  fl_value_set_string_take(layout, "maximized",
                           fl_value_new_bool(self->maximized));
  return layout;
}

void desktop_window_forget_press(DesktopWindow* self) {
  g_clear_pointer(&self->press, gdk_event_free);
  if (self->press_widget != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(self->press_widget),
                                 reinterpret_cast<gpointer*>(&self->press_widget));
    self->press_widget = nullptr;
  }
}

gboolean desktop_window_record_press(GSignalInvocationHint*, guint n_values,
                                     const GValue* values, gpointer data) {
  auto* self = static_cast<DesktopWindow*>(data);
  if (n_values < 2) return TRUE;
  auto* widget = GTK_WIDGET(g_value_get_object(&values[0]));
  auto* event = static_cast<GdkEvent*>(g_value_get_boxed(&values[1]));
  if (event == nullptr || event->type != GDK_BUTTON_PRESS ||
      gtk_widget_get_toplevel(widget) != GTK_WIDGET(self->window)) {
    return TRUE;
  }
  desktop_window_forget_press(self);
  self->press = gdk_event_copy(event);
  self->press_widget = widget;
  g_object_add_weak_pointer(G_OBJECT(widget),
                            reinterpret_cast<gpointer*>(&self->press_widget));
  return TRUE;
}

void desktop_window_start_move(DesktopWindow* self) {
  if (self->press == nullptr || self->press_widget == nullptr) return;
  const GdkEventButton& press = self->press->button;
  gtk_window_begin_move_drag(self->window, press.button,
                             static_cast<gint>(press.x_root),
                             static_cast<gint>(press.y_root), press.time);
  // 窗口管理器接管指针后不再送来松开事件；补发给 Flutter 视图以结束这次按下。
  GdkEvent* release = gdk_event_copy(self->press);
  release->button.type = GDK_BUTTON_RELEASE;
  gboolean handled = FALSE;
  g_signal_emit_by_name(self->press_widget, "button-release-event", release,
                        &handled);
  gdk_event_free(release);
  desktop_window_forget_press(self);
}

gboolean desktop_window_state_changed(GtkWidget*, GdkEventWindowState* event,
                                      gpointer data) {
  auto* self = static_cast<DesktopWindow*>(data);
  if ((event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) == 0) return FALSE;
  self->maximized =
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  g_autoptr(FlValue) layout = desktop_window_layout(self);
  fl_method_channel_invoke_method(self->channel, "layoutChanged", layout,
                                  nullptr, nullptr, nullptr);
  return FALSE;
}

void handle_desktop_window(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* self = static_cast<DesktopWindow*>(data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_str_equal(method, "layout")) {
    g_autoptr(FlValue) layout = desktop_window_layout(self);
    fl_method_call_respond_success(call, layout, nullptr);
    return;
  }
  if (g_str_equal(method, "activate")) {
    gtk_window_present(self->window);
  } else if (g_str_equal(method, "minimize")) {
    gtk_window_iconify(self->window);
  } else if (g_str_equal(method, "toggleMaximized")) {
    if (gtk_window_is_maximized(self->window)) {
      gtk_window_unmaximize(self->window);
    } else {
      gtk_window_maximize(self->window);
    }
  } else if (g_str_equal(method, "close")) {
    // 与系统关闭键相同，发出 delete-event。
    gtk_window_close(self->window);
  } else if (g_str_equal(method, "move")) {
    desktop_window_start_move(self);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void desktop_window_dispose(gpointer data) {
  auto* self = static_cast<DesktopWindow*>(data);
  if (self->press_hook != 0) {
    g_signal_remove_emission_hook(
        g_signal_lookup("button-press-event", GTK_TYPE_WIDGET),
        self->press_hook);
  }
  desktop_window_forget_press(self);
  if (self->state_changed != 0) {
    g_signal_handler_disconnect(self->window, self->state_changed);
  }
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                            nullptr);
  g_object_unref(self->channel);
  g_object_unref(self->window);
  delete self;
}

// title_bar 为 true 时由 Flutter 绘制标题栏，只用于主窗口。
void register_desktop_window(FlView* view, bool title_bar) {
  auto* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  gtk_window_set_title(window, APP_DISPLAY_NAME);
  gtk_widget_set_size_request(GTK_WIDGET(view), 400, 300);

  auto* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* self = new DesktopWindow{
      GTK_WINDOW(g_object_ref(window)),
      fl_method_channel_new(messenger, "dev.scrcpyconnect/desktop_window",
                            FL_METHOD_CODEC(codec)),
      title_bar,
      gtk_window_is_maximized(window) != FALSE,
      0,
      0,
      nullptr,
      nullptr};
  fl_method_channel_set_method_call_handler(self->channel,
                                            handle_desktop_window, self, nullptr);
  if (title_bar) {
    self->state_changed =
        g_signal_connect(window, "window-state-event",
                         G_CALLBACK(desktop_window_state_changed), self);
    // Flutter 视图内部的事件盒先收到按下；用发射钩子记录，不改变其处理。
    self->press_hook = g_signal_add_emission_hook(
        g_signal_lookup("button-press-event", GTK_TYPE_WIDGET), 0,
        desktop_window_record_press, self, nullptr);
  }
  g_object_set_data_full(G_OBJECT(view), "desktop-window", self,
                         desktop_window_dispose);
  g_signal_connect(
      view, "destroy", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
        // 在视图释放引擎之前注销 messenger 与 GTK 回调。
        g_object_set_data(G_OBJECT(widget), "desktop-window", nullptr);
      }),
      nullptr);
}

}  // namespace

// 收到 Flutter 首帧时调用。
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// 实现 GApplication::activate。
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_default_size(window, 1280, 720);
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icons = g_build_filename(directory, "share", "icons", nullptr);
    gtk_icon_theme_append_search_path(gtk_icon_theme_get_default(), icons);
  }
  gtk_window_set_default_icon_name(APPLICATION_ID);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  register_system_typography(view);
  GdkRGBA background_color;
  // 背景默认为黑色；需要透明背景时可改为 #00000000。
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  // 不显示的空标题栏保留客户端装饰的阴影与缩放边框，标题栏由 Flutter 绘制。
  gtk_window_set_titlebar(window, gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(view));
  register_desktop_window(view, true);

  // Flutter 开始绘制后显示窗口；视图必须先实现，才能开始渲染。
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(
      [](FlPluginRegistry* registry) {
        // The plugin has already realized the child view with its own titlebar.
        register_desktop_window(FL_VIEW(registry), false);
        fl_register_plugins(registry);
      });

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// 实现 GApplication::local_command_line。
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // 首个参数是程序名称，读取命令行时跳过。
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// 实现 GObject::dispose。
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // 使用应用 ID 作为进程名，帮助 GTK 与桌面环境关联对应的 .desktop 文件，使系统能以应用身份识别运行进程。
  g_set_prgname(APPLICATION_ID);
  g_set_application_name(APP_DISPLAY_NAME);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
