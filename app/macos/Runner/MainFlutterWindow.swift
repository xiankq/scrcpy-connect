import Cocoa
import FlutterMacOS
import desktop_multi_window
import ObjectiveC

class MainFlutterWindow: NSWindow {
  private static var childServicesKey: UInt8 = 0
  private var visualPreferences: SystemVisualPreferences?
  private var environmentEvents: WindowEnvironmentEvents?
  private var platformMethods: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      MainFlutterWindow.installChildServices(on: controller)
    }
    visualPreferences = SystemVisualPreferences(messenger: flutterViewController.engine.binaryMessenger)
    environmentEvents = WindowEnvironmentEvents(
      window: self, messenger: flutterViewController.engine.binaryMessenger)
    let platform = FlutterMethodChannel(
      name: "dev.scrcpyconnect/platform", binaryMessenger: flutterViewController.engine.binaryMessenger)
    platform.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Window is closed", details: nil))
        return
      }
      if call.method == "window.readEnvironment" {
        let bounds = self.contentView?.bounds ?? .zero
        result([
          "width": bounds.width,
          "height": bounds.height,
          "windowId": "macos:\(self.windowNumber)",
          "mode": self.styleMask.contains(.fullScreen) ? "fullScreen" : "freeform",
        ])
        return
      }
      guard call.method == "window.openIndependent" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result([
        "supported": false,
        "reason": "macOS 原生独立窗口需独立 Flutter 引擎；当前回退为同页控制会话",
      ])
    }
    platformMethods = platform

    super.awakeFromNib()
  }

  deinit {
    platformMethods?.setMethodCallHandler(nil)
    visualPreferences?.dispose()
    environmentEvents?.dispose()
  }

  private static func installChildServices(on controller: FlutterViewController) {
    let services = MacOSWindowServices(controller: controller)
    objc_setAssociatedObject(
      controller,
      &childServicesKey,
      services,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
  }
}

/// Child engines do not pass through [MainFlutterWindow.awakeFromNib]. Keep
/// the same host contracts attached to the child controller so accessibility
/// preferences and live window geometry remain identical across windows.
private final class MacOSWindowServices {
  private let visualPreferences: SystemVisualPreferences
  private let environmentEvents: WindowEnvironmentEvents?
  private let platformMethods: FlutterMethodChannel
  private weak var window: NSWindow?

  init(controller: FlutterViewController) {
    let messenger = controller.engine.binaryMessenger
    visualPreferences = SystemVisualPreferences(messenger: messenger)
    window = controller.view.window
    if let window {
      environmentEvents = WindowEnvironmentEvents(window: window, messenger: messenger)
    } else {
      environmentEvents = nil
    }
    platformMethods = FlutterMethodChannel(
      name: "dev.scrcpyconnect/platform", binaryMessenger: messenger)
    platformMethods.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "Window is closed", details: nil))
        return
      }
      guard call.method == "window.readEnvironment" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let bounds = self.window?.contentView?.bounds ?? .zero
      let windowId = self.window.map { "macos:\($0.windowNumber)" } ?? "macos:child"
      result([
        "width": bounds.width,
        "height": bounds.height,
        "windowId": windowId,
        "mode": self.window?.styleMask.contains(.fullScreen) == true
            ? "fullScreen"
            : "freeform",
      ])
    }
  }

  deinit {
    platformMethods.setMethodCallHandler(nil)
    visualPreferences.dispose()
    environmentEvents?.dispose()
  }
}

/// Publishes the same window geometry contract as the mobile hosts. Flutter
/// still re-reads on metrics changes; this stream covers native window mode
/// transitions that do not necessarily produce a Flutter frame immediately.
private final class WindowEnvironmentEvents: NSObject, FlutterStreamHandler {
  private weak var window: NSWindow?
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []
  private var generation: Int64 = 0

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    events = FlutterEventChannel(
      name: "dev.scrcpyconnect/window_environment/events", binaryMessenger: messenger)
    super.init()
    events.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink)
    -> FlutterError?
  {
    stopObserving()
    sink = eventSink
    let listeningGeneration = generation
    sendSnapshot()
    guard let window else { return nil }
    let names: [Notification.Name] = [
      NSWindow.didResizeNotification,
      NSWindow.didMoveNotification,
      NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didChangeScreenNotification,
    ]
    observers = names.map { name in
      NotificationCenter.default.addObserver(
        forName: name, object: window, queue: .main
      ) { [weak self] _ in
        guard let self, self.generation == listeningGeneration else { return }
        self.sendSnapshot()
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopObserving()
    return nil
  }

  private func sendSnapshot() {
    guard let window else { return }
    let bounds = window.contentView?.bounds ?? .zero
    sink?([
      "width": bounds.width,
      "height": bounds.height,
      "windowId": "macos:\(window.windowNumber)",
      "mode": window.styleMask.contains(.fullScreen) ? "fullScreen" : "freeform",
    ])
  }

  private func stopObserving() {
    generation += 1
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
    sink = nil
  }

  func dispose() {
    stopObserving()
    events.setStreamHandler(nil)
  }
}

private final class SystemVisualPreferences: NSObject, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var observer: NSObjectProtocol?
  private var revision: Int64 = 0
  private var generation: Int64 = 0

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(
      name: "dev.scrcpyconnect/visual_preferences", binaryMessenger: messenger)
    events = FlutterEventChannel(
      name: "dev.scrcpyconnect/visual_preferences/events", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async { [weak self] in
        guard let self = self else {
          result(FlutterError(code: "unavailable", message: "Window is closed", details: nil))
          return
        }
        result(self.snapshot())
      }
    }
    events.setStreamHandler(self)
  }

  @MainActor
  private func snapshot() -> [String: Any] {
    revision += 1
    return [
      "revision": revision,
      "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
    ]
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    stopObserving()
    sink = events
    let listeningGeneration = generation
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.generation == listeningGeneration else { return }
      self.observer = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        DispatchQueue.main.async { [weak self] in
          guard let self = self, self.generation == listeningGeneration else { return }
          self.sink?(self.snapshot())
        }
      }
      self.sink?(self.snapshot())
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopObserving()
    return nil
  }

  private func stopObserving() {
    generation += 1
    if let observer = observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observer = nil
    sink = nil
  }

  func dispose() {
    stopObserving()
    methods.setMethodCallHandler(nil)
    events.setStreamHandler(nil)
  }
}
