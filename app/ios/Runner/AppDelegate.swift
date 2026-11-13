import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let platform = FlutterMethodChannel(
      name: "dev.scrcpyconnect/platform", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    platform.setMethodCallHandler { call, result in
      if call.method == "window.readEnvironment" {
        let scene = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .first { $0.activationState != .unattached }
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        guard let window = window, let scene = scene else {
          result(nil)
          return
        }
        let bounds = window.bounds
        let safe = window.safeAreaInsets
        result([
          "width": bounds.width,
          "height": bounds.height,
          "windowId": scene.session.persistentIdentifier,
          "insets": [
            "left": safe.left,
            "top": safe.top,
            "right": safe.right,
            "bottom": safe.bottom,
          ],
        ])
        return
      }
      guard call.method == "window.openIndependent" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result([
        "supported": false,
        "reason": "iOS 独立场景需宿主提供独立 Flutter 引擎；当前回退为同页控制会话",
      ])
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SystemVisualPreferences") {
      SystemVisualPreferences.register(with: registrar)
    }
  }
}

private final class SystemVisualPreferences: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observer: NSObjectProtocol?
  private var revision: Int64 = 0
  private var generation: Int64 = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SystemVisualPreferences()
    let methods = FlutterMethodChannel(
      name: "dev.scrcpyconnect/visual_preferences", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    registrar.publish(instance)
    let events = FlutterEventChannel(
      name: "dev.scrcpyconnect/visual_preferences/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "read" else {
      result(FlutterMethodNotImplemented)
      return
    }
    DispatchQueue.main.async { result(self.snapshot()) }
  }

  @MainActor
  private func snapshot() -> [String: Any] {
    revision += 1
    return [
      "revision": revision,
      "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
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
      // 先注册通知再读取，避免读取和开始监听之间丢失系统变更。
      self.observer = NotificationCenter.default.addObserver(
        forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
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

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    stopObserving()
  }

  private func stopObserving() {
    generation += 1
    if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    sink = nil
  }

  deinit { stopObserving() }
}
