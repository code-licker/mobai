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
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "com.example.mobai/download_notifications",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getDeviceRamMb":
        let totalMb = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        result(totalMb)
      case "openUrl":
        guard
          let args = call.arguments as? [String: Any],
          let rawUrl = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let url = URL(string: rawUrl),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
        else {
          result(false)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
