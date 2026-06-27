import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.engine.binaryMessenger
    let channel = FlutterMethodChannel(
      name: "io.github.caolib.kira/app_icon",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setAppIcon":
        let index = call.arguments as? [String: Any]
        let idx = index?["index"] as? Int ?? 0
        let iconName = idx == 0 ? nil : "AppIcon-1"
        UIApplication.shared.setAlternateIconName(iconName) { error in
          if let error = error {
            result(FlutterError(code: "icon_error", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      case "getAppIconIndex":
        let current = UIApplication.shared.alternateIconName
        result(current == nil ? 0 : 1)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
