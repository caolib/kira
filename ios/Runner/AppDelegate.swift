import CoreFoundation
import Flutter
import UIKit
import flutter_foreground_task

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // UIScene initializes plugins later; BGTask registration must happen before launch completes.
    SwiftFlutterForegroundTaskPlugin.registerAppRefreshForBackgroundLaunch()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "io.github.caolib.kira/app_icon",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { (call, result) in
      let handleCall = {
        switch call.method {
        case "setAppIcon":
          guard let arguments = call.arguments as? [String: Any],
                let number = arguments["index"] as? NSNumber,
                CFGetTypeID(number) != CFBooleanGetTypeID(),
                let index = arguments["index"] as? Int,
                index == 0 || index == 1 else {
            result(FlutterError(
              code: "invalid_icon_index",
              message: "应用图标索引必须为 0 或 1。",
              details: nil
            ))
            return
          }
          let application = UIApplication.shared
          guard application.supportsAlternateIcons else {
            result(FlutterError(
              code: "alternate_icons_unavailable",
              message: "当前设备或应用配置不支持切换图标。",
              details: nil
            ))
            return
          }
          let iconName: String? = index == 0 ? nil : "AppIcon-1"
          if application.alternateIconName == iconName {
            result(nil)
            return
          }
          application.setAlternateIconName(iconName) { error in
            // UIKit may invoke the completion on a background queue.
            DispatchQueue.main.async {
              if let error = error {
                result(FlutterError(
                  code: "icon_error",
                  message: error.localizedDescription,
                  details: nil
                ))
              } else {
                result(nil)
              }
            }
          }
        case "getAppIconIndex":
          switch UIApplication.shared.alternateIconName {
          case nil:
            result(0)
          case "AppIcon-1":
            result(1)
          case let iconName?:
            result(FlutterError(
              code: "unknown_app_icon",
              message: "无法识别当前应用图标。",
              details: iconName
            ))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      if Thread.isMainThread {
        handleCall()
      } else {
        DispatchQueue.main.async(execute: handleCall)
      }
    }
  }
}
