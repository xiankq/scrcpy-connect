import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var flutterEngine: FlutterEngine?
  private var restorationInitialRoute: String?
  private var restorationWindowId: String?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    let activity = connectionOptions.userActivities.first
      ?? session.stateRestorationActivity
    let initialRoute = activity?.userInfo?["initialRoute"] as? String
    let windowId = activity?.userInfo?["windowId"] as? String
    restorationInitialRoute = initialRoute
    restorationWindowId = windowId
    let engine = appDelegate.makeEngine(initialRoute: initialRoute)
    flutterEngine = engine
    window = UIWindow(windowScene: windowScene)
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    window?.rootViewController = controller
    window?.makeKeyAndVisible()
    if let window = window {
      appDelegate.configure(engine: engine, window: window, windowId: windowId)
    }
    registerSceneLifeCycle(with: engine)
    appDelegate.registerScene(session: session, engine: engine, windowId: windowId)
    windowScene.title = activity?.title
    appDelegate.refreshEnvironment(for: engine)
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    refreshEnvironment()
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    refreshEnvironment()
  }

  func scene(
    _ scene: UIScene,
    didUpdate previousCoordinateSpace: UICoordinateSpace,
    interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
    traitCollection previousTraitCollection: UITraitCollection
  ) {
    refreshEnvironment()
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    super.sceneDidDisconnect(scene)
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
      let engine = flutterEngine else { return }
    appDelegate.removeEnvironment(for: engine)
    unregisterSceneLifeCycle(with: engine)
    flutterEngine = nil
    if let id = restorationWindowId {
      window?.rootViewController = nil
      engine.destroyContext()
      appDelegate.remoteSceneDestroyed(id)
    }
  }

  override func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    guard let initialRoute = restorationInitialRoute, !initialRoute.isEmpty else {
      return nil
    }
    let activity = NSUserActivity(activityType: "dev.scrcpyconnect.remote-window")
    activity.userInfo = [
      "initialRoute": initialRoute,
      "windowId": restorationWindowId
        ?? (scene.session.persistentIdentifier),
    ]
    return activity
  }

  private func refreshEnvironment() {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
      let engine = flutterEngine else { return }
    appDelegate.refreshEnvironment(for: engine)
  }

}
