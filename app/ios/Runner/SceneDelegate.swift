import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var flutterEngine: FlutterEngine?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    let activity = connectionOptions.userActivities.first
    let initialRoute = activity?.userInfo?["initialRoute"] as? String
    let windowId = activity?.userInfo?["windowId"] as? String
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
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    if let engine = flutterEngine {
      unregisterSceneLifeCycle(with: engine)
    }
    flutterEngine = nil
    super.sceneDidDisconnect(scene)
  }

}
