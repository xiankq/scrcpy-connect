import Cocoa
import FlutterMacOS
import desktop_multi_window
import ObjectiveC

class MainFlutterWindow: NSWindow {
  private static var childServicesKey: UInt8 = 0
  private var visualPreferences: SystemVisualPreferences?
  private var environmentEvents: WindowEnvironmentEvents?
  private var platformMethods: FlutterMethodChannel?
  private var windowChrome: DesktopWindowChrome?
  private let fileShare = WindowFileShare()

  override func awakeFromNib() {
    let engine = FlutterEngine(name: "Interconnect", project: nil)
    let flutterViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    // Opt in before the engine starts, then keep the primary controller on the
    // implicit view used by Flutter 3.50's macOS accessibility bridge.
    let enableMultiView = NSSelectorFromString("enableMultiView")
    if engine.responds(to: enableMultiView) {
      engine.viewController = nil
      _ = engine.perform(enableMultiView)
      engine.viewController = flutterViewController
    }
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    windowChrome = DesktopWindowChrome(
      window: self, messenger: flutterViewController.engine.binaryMessenger)

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
      if call.method == "documents.shareFile" {
        self.fileShare.show(call.arguments, result: result)
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

/// The share_plus macOS picker uses the implicit view. Choose the caller's
/// actual view when the engine has several windows.
private final class WindowFileShare: NSObject, NSSharingServicePickerDelegate {
  private var picker: NSSharingServicePicker?
  private var completion: FlutterResult?

  func show(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let data = arguments as? [String: Any],
      let path = data["path"] as? String,
      let viewId = data["viewId"] as? NSNumber,
      let window = NSApp.keyWindow,
      let controller = window.contentViewController as? FlutterViewController,
      controller.viewIdentifier == viewId.int64Value else {
      result(FlutterError(code: "window_unavailable", message: "请切回原窗口后再分享。", details: nil))
      return
    }
    guard picker == nil else {
      result(FlutterError(code: "share_in_progress", message: "请先关闭已打开的系统分享面板。", details: nil))
      return
    }
    let view = controller.view
    let bounds = view.bounds
    let origin = NSRect(
      x: data["x"] as? Double ?? bounds.midX,
      y: data["y"] as? Double ?? bounds.midY,
      width: data["width"] as? Double ?? 1,
      height: data["height"] as? Double ?? 1)
    let picker = NSSharingServicePicker(items: [URL(fileURLWithPath: path)])
    picker.delegate = self
    self.picker = picker
    completion = result
    picker.show(relativeTo: origin, of: view, preferredEdge: .maxY)
  }

  func sharingServicePicker(
    _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
  ) {
    let result = completion
    completion = nil
    picker = nil
    result?(["selected": service != nil])
  }
}

/// Child engines do not pass through [MainFlutterWindow.awakeFromNib]. Keep
/// the same host contracts attached to the child controller so accessibility
/// preferences and live window geometry remain identical across windows.
private final class MacOSWindowServices {
  private let visualPreferences: SystemVisualPreferences
  private let environmentEvents: WindowEnvironmentEvents?
  private let platformMethods: FlutterMethodChannel
  private let windowChrome: DesktopWindowChrome?
  private weak var window: NSWindow?

  init(controller: FlutterViewController) {
    let messenger = controller.engine.binaryMessenger
    visualPreferences = SystemVisualPreferences(messenger: messenger)
    window = controller.view.window
    if let window {
      environmentEvents = WindowEnvironmentEvents(window: window, messenger: messenger)
      windowChrome = DesktopWindowChrome(window: window, messenger: messenger)
    } else {
      environmentEvents = nil
      windowChrome = nil
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

private final class DesktopWindowChrome {
  private let methods: FlutterMethodChannel
  private var observers: [NSObjectProtocol] = []
  private var dragMonitor: Any?
  private var dragOffset: NSPoint?
  private var dragLocation = NSPoint.zero
  private var dragging = false
  private static let compactWidth: CGFloat = 600

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    window.contentMinSize = NSSize(width: 400, height: 300)
    window.isMovableByWindowBackground = false
    window.collectionBehavior.insert(.fullScreenPrimary)
    methods = FlutterMethodChannel(
      name: "dev.scrcpyconnect/desktop_window", binaryMessenger: messenger)
    Self.updateChrome(window)
    methods.setMethodCallHandler { [weak self, weak window] call, result in
      guard let window else {
        result(FlutterError(code: "unavailable", message: "Window is closed", details: nil))
        return
      }
      switch call.method {
      case "layout":
        result(Self.layout(of: window))
        return
      case "toggleMaximized":
        guard !window.styleMask.contains(.fullScreen) else { result(nil); return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.miniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
      case "activate":
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
      case "move":
        if let self, self.dragOffset != nil, !window.styleMask.contains(.fullScreen) {
          self.dragging = true
          self.move(window)
        }
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
    // Flutter identifies the drag region after pointer events reach the engine.
    // Keep the initial pointer offset and track the remainder in AppKit.
    dragMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
    ) { [weak self, weak window] event in
      guard let self, let window, event.window === window else { return event }
      switch event.type {
      case .leftMouseDown:
        self.dragging = false
        self.dragOffset = event.locationInWindow
        self.dragLocation = window.convertPoint(toScreen: event.locationInWindow)
      case .leftMouseDragged, .leftMouseUp:
        self.dragLocation = window.convertPoint(toScreen: event.locationInWindow)
        if self.dragging { self.move(window) }
        // A quick drag can end before the engine's move request arrives.
        // Keep its final location until the next press.
        if event.type == .leftMouseUp { self.dragging = false }
      default:
        break
      }
      return event
    }
    observers = [
      NSWindow.didResizeNotification,
      NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification,
    ]
      .map { name in
        NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
          [weak self, weak window] _ in
          guard let window else { return }
          Self.updateChrome(window)
          self?.publishLayout(window)
        }
      }
  }

  private var lastLayout: [String: CGFloat]?

  private func publishLayout(_ window: NSWindow) {
    let layout = Self.layout(of: window)
    guard layout != lastLayout else { return }
    lastLayout = layout
    methods.invokeMethod("layoutChanged", arguments: layout)
  }

  private static func updateChrome(_ window: NSWindow) {
    guard !window.styleMask.contains(.fullScreen) else { return }
    let immersive = window.frame.width >= compactWidth
    guard immersive != window.styleMask.contains(.fullSizeContentView) else { return }
    // Set the appearance before changing the content rectangle, which can
    // synchronously emit another resize notification.
    window.titleVisibility = immersive ? .hidden : .visible
    window.titlebarAppearsTransparent = immersive
    window.titlebarSeparatorStyle = immersive ? .none : .automatic
    if immersive {
      window.styleMask.insert(.fullSizeContentView)
    } else {
      window.styleMask.remove(.fullSizeContentView)
    }
  }

  private func move(_ window: NSWindow) {
    guard let dragOffset else { return }
    window.setFrameOrigin(
      NSPoint(x: dragLocation.x - dragOffset.x, y: dragLocation.y - dragOffset.y))
  }

  private static func layout(of window: NSWindow) -> [String: CGFloat] {
    guard !window.styleMask.contains(.fullScreen),
      window.styleMask.contains(.fullSizeContentView), let content = window.contentView else {
      return ["left": 0, "right": 0, "top": 0]
    }
    let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
      .compactMap { window.standardWindowButton($0) }
      .filter { !$0.isHidden }
      .map { content.convert($0.bounds, from: $0) }
    let top = buttons.map { content.isFlipped ? $0.maxY : content.bounds.maxY - $0.minY }
    return ["left": buttons.map(\.maxX).max() ?? 0, "right": 0, "top": top.max() ?? 0]
  }

  deinit {
    methods.setMethodCallHandler(nil)
    observers.forEach(NotificationCenter.default.removeObserver)
    if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
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
