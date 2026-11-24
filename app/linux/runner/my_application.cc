#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <algorithm>
#include <string>

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
  GtkWidget* titlebar;
  GtkWidget* start;
  GtkWidget* end;
};

constexpr int kCompactWidth = 600;

FlValue* desktop_window_layout(const DesktopWindow* chrome) {
  GtkRequisition start = {}, end = {};
  if (chrome->start != nullptr && gtk_widget_get_visible(chrome->start)) {
    gtk_widget_get_preferred_size(chrome->start, nullptr, &start);
    gtk_widget_get_preferred_size(chrome->end, nullptr, &end);
  }
  const bool rtl = gtk_widget_get_direction(GTK_WIDGET(chrome->window)) ==
                   GTK_TEXT_DIR_RTL;
  auto* layout = fl_value_new_map();
  fl_value_set_string_take(layout, "left",
                           fl_value_new_int(rtl ? end.width : start.width));
  fl_value_set_string_take(layout, "right",
                           fl_value_new_int(rtl ? start.width : end.width));
  fl_value_set_string_take(layout, "top",
                           fl_value_new_int(std::max(start.height, end.height)));
  return layout;
}

void handle_desktop_window(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* chrome = static_cast<DesktopWindow*>(data);
  auto* window = chrome->window;
  const gchar* method = fl_method_call_get_name(call);
  if (g_str_equal(method, "layout")) {
    g_autoptr(FlValue) layout = desktop_window_layout(chrome);
    fl_method_call_respond_success(call, layout, nullptr);
    return;
  }
  if (g_str_equal(method, "activate")) {
    gtk_window_present(window);
  } else if (g_str_equal(method, "toggleMaximized")) {
    if (gtk_window_is_maximized(window)) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
  } else if (g_str_equal(method, "move")) {
    auto* display = gtk_widget_get_display(GTK_WIDGET(window));
    auto* pointer = gdk_seat_get_pointer(gdk_display_get_default_seat(display));
    gint x, y;
    gdk_device_get_position(pointer, nullptr, &x, &y);
    gdk_window_begin_move_drag_for_device(
        gtk_widget_get_window(GTK_WIDGET(window)), pointer, 1, x, y,
        GDK_CURRENT_TIME);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void publish_desktop_window_layout(FlMethodChannel* channel) {
  auto* chrome = static_cast<DesktopWindow*>(
      g_object_get_data(G_OBJECT(channel), "desktop-window"));
  g_autoptr(FlValue) layout = desktop_window_layout(chrome);
  fl_method_channel_invoke_method(channel, "layoutChanged", layout, nullptr,
                                   nullptr, nullptr);
}

void update_desktop_chrome(FlMethodChannel* channel, int width) {
  auto* chrome = static_cast<DesktopWindow*>(
      g_object_get_data(G_OBJECT(channel), "desktop-window"));
  auto* surface = gtk_widget_get_window(GTK_WIDGET(chrome->window));
  const bool fullscreen = surface != nullptr &&
      (gdk_window_get_state(surface) & GDK_WINDOW_STATE_FULLSCREEN);
  const bool immersive = !fullscreen && width >= kCompactWidth;
  const bool title = !fullscreen && !immersive;
  if (gtk_widget_get_visible(chrome->titlebar) == title &&
      gtk_widget_get_visible(chrome->start) == immersive) return;
  gtk_widget_set_visible(chrome->titlebar, title);
  gtk_widget_set_visible(chrome->start, immersive);
  gtk_widget_set_visible(chrome->end, immersive);
  publish_desktop_window_layout(channel);
}

void register_desktop_window(FlView* view, GtkWidget* start = nullptr,
                             GtkWidget* end = nullptr, GtkWidget* titlebar = nullptr) {
  auto* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  gtk_window_set_title(window, APP_DISPLAY_NAME);
  gtk_widget_set_size_request(GTK_WIDGET(view), 400, 300);

  auto* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(
      messenger, "dev.scrcpyconnect/desktop_window", FL_METHOD_CODEC(codec));
  auto* chrome = new DesktopWindow{window, titlebar, start, end};
  g_object_set_data_full(G_OBJECT(channel), "desktop-window", chrome,
                         +[](gpointer data) {
                           delete static_cast<DesktopWindow*>(data);
                         });
  fl_method_channel_set_method_call_handler(channel, handle_desktop_window,
                                            chrome, nullptr);
  if (start != nullptr) {
    g_signal_connect_object(
        view, "size-allocate",
        G_CALLBACK(+[](GtkWidget*, GtkAllocation* allocation, FlMethodChannel* channel) {
          update_desktop_chrome(channel, allocation->width);
        }),
        channel, static_cast<GConnectFlags>(0));
    for (auto* header : {start, end}) {
      g_signal_connect_object(
          header, "size-allocate",
          G_CALLBACK(+[](GtkWidget*, GtkAllocation*, FlMethodChannel* channel) {
            publish_desktop_window_layout(channel);
          }),
          channel, static_cast<GConnectFlags>(0));
    }
    g_signal_connect_object(
        window, "window-state-event",
        G_CALLBACK(+[](GtkWidget* window, GdkEventWindowState*,
                       FlMethodChannel* channel) -> gboolean {
          update_desktop_chrome(channel, gtk_widget_get_allocated_width(window));
          return FALSE;
        }),
        channel, static_cast<GConnectFlags>(0));
  }
  g_signal_connect(
      view, "destroy", G_CALLBACK(+[](GtkWidget*, FlMethodChannel* channel) {
        fl_method_channel_set_method_call_handler(channel, nullptr, nullptr,
                                                  nullptr);
        g_object_unref(channel);
      }),
      channel);
}

void update_button_layout(GtkSettings* settings, GParamSpec*, GtkWidget* overlay) {
  auto* start = GTK_HEADER_BAR(g_object_get_data(G_OBJECT(overlay), "start"));
  auto* end = GTK_HEADER_BAR(g_object_get_data(G_OBJECT(overlay), "end"));
  g_autofree gchar* layout = nullptr;
  g_object_get(settings, "gtk-decoration-layout", &layout, nullptr);
  const std::string order(layout);
  const auto split = order.find(':');
  const auto left = order.substr(0, split) + ":";
  const auto right = split == std::string::npos ? ":" : order.substr(split);
  gtk_header_bar_set_decoration_layout(start, left.c_str());
  gtk_header_bar_set_decoration_layout(end, right.c_str());
}

GtkWidget* add_window_buttons(GtkOverlay* overlay, GtkAlign edge) {
  auto* header = gtk_header_bar_new();
  gtk_header_bar_set_custom_title(GTK_HEADER_BAR(header),
                                  gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
  gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header), TRUE);
  gtk_widget_set_halign(header, edge);
  gtk_widget_set_valign(header, GTK_ALIGN_START);

  g_autoptr(GtkCssProvider) style = gtk_css_provider_new();
  gtk_css_provider_load_from_data(
      style,
      "headerbar { background: transparent; border: 0; box-shadow: none; "
      "min-height: 0; padding: 0; }", -1, nullptr);
  gtk_style_context_add_provider(gtk_widget_get_style_context(header),
                                 GTK_STYLE_PROVIDER(style),
                                 GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  gtk_overlay_add_overlay(overlay, header);
  gtk_widget_show(header);
  return header;
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
  // Install the GTK titlebar before realization. Wide windows hide it and
  // show the same themed controls above the Flutter surface instead.
  auto* titlebar = gtk_header_bar_new();
  gtk_header_bar_set_title(GTK_HEADER_BAR(titlebar), APP_DISPLAY_NAME);
  gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(titlebar), TRUE);
  gtk_widget_set_no_show_all(titlebar, TRUE);
  gtk_window_set_titlebar(window, titlebar);
  auto* overlay = GTK_OVERLAY(gtk_overlay_new());
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  auto* start = add_window_buttons(overlay, GTK_ALIGN_START);
  auto* end = add_window_buttons(overlay, GTK_ALIGN_END);
  g_object_set_data(G_OBJECT(overlay), "start", start);
  g_object_set_data(G_OBJECT(overlay), "end", end);
  auto* settings = gtk_widget_get_settings(GTK_WIDGET(window));
  g_signal_connect_object(settings, "notify::gtk-decoration-layout",
                           G_CALLBACK(update_button_layout), overlay,
                           static_cast<GConnectFlags>(0));
  update_button_layout(settings, nullptr, GTK_WIDGET(overlay));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(overlay));
  gtk_widget_show(GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(overlay));
  register_desktop_window(view, start, end, titlebar);

  // Flutter 开始绘制后显示窗口；视图必须先实现，才能开始渲染。
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(
      [](FlPluginRegistry* registry) {
        // The plugin has already realized the child view with its own titlebar.
        register_desktop_window(FL_VIEW(registry));
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
