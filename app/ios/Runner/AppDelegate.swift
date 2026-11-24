import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let engineGroup = FlutterEngineGroup(name: "scrcpy_connect", project: nil)
  private var workbenchEngine: FlutterEngine?
  private var workbenchSession: UISceneSession?
  private var workbenchMessenger: FlutterBinaryMessenger?
  private var remoteSessions: [String: UISceneSession] = [:]
  private var windowRequests: [String: [FlutterResult]] = [:]
  private var environmentEventHandlers: [ObjectIdentifier: WindowEnvironmentEvents] = [:]

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
      engine: nil,
      messenger: engineBridge.applicationRegistrar.messenger(),
      registry: engineBridge.pluginRegistry,
      windowProvider: { AppDelegate.activeWindow() },
      windowIdProvider: { nil })
  }

  func makeEngine(initialRoute: String?) -> FlutterEngine {
    if initialRoute == nil, let engine = workbenchEngine {
      return engine
    }
    let engine = engineGroup.makeEngine(
      withEntrypoint: nil,
      libraryURI: nil,
      initialRoute: initialRoute)
    GeneratedPluginRegistrant.register(with: engine)
    if initialRoute == nil { workbenchEngine = engine }
    return engine
  }

  func configure(engine: FlutterEngine, window: UIWindow, windowId: String? = nil) {
    registerPlatformChannels(
      engine: engine,
      messenger: engine.binaryMessenger,
      registry: engine,
      windowProvider: { [weak window] in window },
      windowIdProvider: { windowId })
  }

  func registerScene(session: UISceneSession, engine: FlutterEngine, windowId: String?) {
    guard let id = windowId else {
      workbenchSession = session
      workbenchMessenger = engine.binaryMessenger
      return
    }
    remoteSessions[id] = session
    let requests = windowRequests.removeValue(forKey: id) ?? []
    for result in requests { result(["supported": true, "windowId": id]) }
  }

  func remoteSceneDestroyed(_ id: String) {
    remoteSessions.removeValue(forKey: id)
    guard let messenger = workbenchMessenger else { return }
    FlutterMethodChannel(name: "dev.scrcpyconnect/window_lifecycle", binaryMessenger: messenger)
      .invokeMethod("destroyed", arguments: id)
  }

  private func registerPlatformChannels(
    engine: FlutterEngine?,
    messenger: FlutterBinaryMessenger,
    registry: FlutterPluginRegistry,
    windowProvider: @escaping () -> UIWindow?,
    windowIdProvider: @escaping () -> String?
  ) {
    let environmentEvents = WindowEnvironmentEvents { [weak self] in
      self?.readEnvironment(
        windowProvider: windowProvider,
        windowIdProvider: windowIdProvider)
    }
    let environmentChannel = FlutterEventChannel(
      name: "dev.scrcpyconnect/window_environment/events",
      binaryMessenger: messenger)
    environmentChannel.setStreamHandler(environmentEvents)
    if let engine = engine {
      environmentEventHandlers[ObjectIdentifier(engine)] = environmentEvents
    }
    let platform = FlutterMethodChannel(
      name: "dev.scrcpyconnect/platform", binaryMessenger: messenger)
    platform.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "app_unavailable", message: "应用宿主已结束。", details: nil))
        return
      }
      if call.method == "window.readEnvironment" {
        guard let environment = self.readEnvironment(
          windowProvider: windowProvider,
          windowIdProvider: windowIdProvider) else {
          result(nil)
          return
        }
        result(environment)
        return
      }
      switch call.method {
      case "window.openIndependent":
        self.openIndependentScene(call, result: result)
      case "window.showWorkbench":
        let application = UIApplication.shared
        let session = self.workbenchSession.flatMap {
          application.openSessions.contains($0) ? $0 : nil
        }
        application.requestSceneSessionActivation(session, userActivity: nil, options: nil)
        result(nil)
      case "window.closeIndependent":
        if let id = (call.arguments as? [String: Any])?["windowId"] as? String,
          let session = self.remoteSessions[id] {
          UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    if let registrar = registry.registrar(forPlugin: "SystemVisualPreferences") {
      SystemVisualPreferences.register(with: registrar)
    }
  }

  func refreshEnvironment(for engine: FlutterEngine) {
    environmentEventHandlers[ObjectIdentifier(engine)]?.emit()
  }

  func removeEnvironment(for engine: FlutterEngine) {
    environmentEventHandlers.removeValue(forKey: ObjectIdentifier(engine))
  }

  private func readEnvironment(
    windowProvider: @escaping () -> UIWindow?,
    windowIdProvider: @escaping () -> String?
  ) -> [String: Any]? {
    guard let window = windowProvider(), let scene = window.windowScene else {
      return nil
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
    return environment
  }

  private func openIndependentScene(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let app = UIApplication.shared
    guard UIDevice.current.userInterfaceIdiom == .pad,
      app.supportsMultipleScenes else {
      result(["supported": false, "reason": "当前系统使用应用内控制页。"])
      return
    }
    guard let arguments = call.arguments as? [String: Any],
      let id = arguments["windowId"] as? String,
      let initialRoute = arguments["initialRoute"] as? String,
      !id.isEmpty, !initialRoute.isEmpty else {
      result(FlutterError(code: "invalid_window_request", message: "独立窗口参数不完整。", details: nil))
      return
    }
    if let session = remoteSessions[id] {
      app.requestSceneSessionActivation(session, userActivity: nil, options: nil)
      result(["supported": true, "windowId": id])
      return
    }
    if windowRequests[id] != nil {
      windowRequests[id]?.append(result)
      return
    }
    windowRequests[id] = [result]
    let activity = NSUserActivity(activityType: "dev.scrcpyconnect.remote-window")
    activity.title = arguments["title"] as? String
    activity.targetContentIdentifier = id
    activity.userInfo = ["initialRoute": initialRoute, "windowId": id]
    app.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { [weak self] _ in
      DispatchQueue.main.async {
        let requests = self?.windowRequests.removeValue(forKey: id) ?? []
        for reply in requests {
          reply(["supported": false, "reason": "当前系统拒绝创建远控窗口。"])
        }
      }
    }
  }

  private static func activeWindow() -> UIWindow? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState != .unattached }
    return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
  }
}

private final class WindowEnvironmentEvents: NSObject, FlutterStreamHandler {
  private let snapshot: () -> [String: Any]?
  private var sink: FlutterEventSink?

  init(snapshot: @escaping () -> [String: Any]?) {
    self.snapshot = snapshot
    super.init()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    events(snapshot())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func emit() {
    sink?(snapshot())
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
