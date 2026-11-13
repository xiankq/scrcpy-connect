import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  private var visualPreferences: SystemVisualPreferences?
  private var platformMethods: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }
    visualPreferences = SystemVisualPreferences(messenger: flutterViewController.engine.binaryMessenger)
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
