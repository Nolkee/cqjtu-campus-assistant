import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let balanceMonitorTaskId = "com.axu.schedule.balanceMonitor"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // BGTaskScheduler registration must complete before launch finishes.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: Self.balanceMonitorTaskId,
      frequency: NSNumber(value: 15 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.applicationRegistrar
    let messenger = registrar.messenger()

    // Official iOS 26 UIGlassEffect Platform Views
    // https://developer.apple.com/documentation/uikit/uiglasseffect
    registrar.register(
      LiquidGlassPlatformViewFactory(messenger: messenger),
      withId: "campus_app/ui_glass_effect"
    )
    registrar.register(
      LiquidGlassTabBarPlatformViewFactory(messenger: messenger),
      withId: "campus_app/liquid_glass_tab_bar"
    )
  }
}
