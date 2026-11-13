import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let engineGroup = FlutterEngineGroup(name: "scrcpy_connect", project: nil)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerPlatformChannels(
      messenger: engineBridge.applicationRegistrar.messenger(),
      registry: engineBridge.pluginRegistry,
      windowProvider: { AppDelegate.activeWindow() },
      windowIdProvider: { nil })
  }

  func makeEngine(initialRoute: String?) -> FlutterEngine {
    let engine = engineGroup.makeEngine(
      withEntrypoint: nil,
      libraryURI: nil,
      initialRoute: initialRoute)
    GeneratedPluginRegistrant.register(with: engine)
    return engine
  }

  func configure(engine: FlutterEngine, window: UIWindow, windowId: String? = nil) {
    registerPlatformChannels(
      messenger: engine.binaryMessenger,
      registry: engine,
      windowProvider: { [weak window] in window },
      windowIdProvider: { windowId })
  }

  private func registerPlatformChannels(
    messenger: FlutterBinaryMessenger,
    registry: FlutterPluginRegistry,
    windowProvider: @escaping () -> UIWindow?,
    windowIdProvider: @escaping () -> String?
  ) {
    let platform = FlutterMethodChannel(
      name: "dev.scrcpyconnect/platform", binaryMessenger: messenger)
    platform.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "app_unavailable", message: "应用宿主已结束。", details: nil))
        return
      }
      if call.method == "window.readEnvironment" {
        guard let window = windowProvider(), let scene = window.windowScene else {
          result(nil)
          return
        }
        let bounds = window.bounds
        let safe = window.safeAreaInsets
        var environment: [String: Any] = [
          "width": bounds.width,
          "height": bounds.height,
          "windowId": windowIdProvider() ?? scene.session.persistentIdentifier,
          "insets": [
            "left": safe.left,
            "top": safe.top,
            "right": safe.right,
            "bottom": safe.bottom,
          ],
        ]
        if #available(iOS 27.1, *) {
          let divisions = window
            .reservedRegions(kind: .division, options: [])
            .filter { $0.isActive }
          environment["displayFeatures"] = divisions.map { region in
            let frame = region.frame
            return [
              "left": frame.minX,
              "top": frame.minY,
              "width": frame.width,
              "height": frame.height,
              "type": "fold",
              "state": frame.width >= frame.height ? "tabletop" : "book",
            ] as [String: Any]
          }
          environment["posture"] = divisions.first.map { region in
            let frame = region.frame
            return frame.width >= frame.height ? "tabletop" : "book"
          } ?? "normal"
        }
        result(environment)
        return
      }
      guard call.method == "window.openIndependent" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.openIndependentScene(call, result: result)
    }
    if let registrar = registry.registrar(forPlugin: "SystemVisualPreferences") {
      SystemVisualPreferences.register(with: registrar)
    }
  }

  private func openIndependentScene(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let deviceId = arguments["deviceId"] as? String,
      let packageName = arguments["packageName"] as? String,
      let sessionId = arguments["sessionId"] as? String,
      let initialRoute = arguments["initialRoute"] as? String,
      !deviceId.isEmpty, !packageName.isEmpty, !sessionId.isEmpty,
      !initialRoute.isEmpty else {
      result(FlutterError(code: "invalid_window_request", message: "独立窗口参数不完整。", details: nil))
      return
    }
    let windowId = UUID().uuidString
    let activity = NSUserActivity(activityType: "dev.scrcpyconnect.remote-window")
    activity.userInfo = [
      "initialRoute": initialRoute,
      "windowId": windowId,
    ]
    UIApplication.shared.requestSceneSessionActivation(
      nil, userActivity: activity, options: nil) { _ in }
    // UIKit only calls the error handler on failure and has no success callback;
    // this response confirms that the scene request was accepted by the host.
    result(["supported": true, "windowId": windowId])
  }

  private static func activeWindow() -> UIWindow? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState != .unattached }
    return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
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
