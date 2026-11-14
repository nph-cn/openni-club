import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var transparencyObserver: NSObjectProtocol?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OpenNIAccessibility") else { return }
    let channel = FlutterMethodChannel(name: "openni/accessibility", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "reduceTransparency" {
        result(UIAccessibility.isReduceTransparencyEnabled)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    if let observer = transparencyObserver { NotificationCenter.default.removeObserver(observer) }
    transparencyObserver = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil, queue: .main
    ) { _ in
      channel.invokeMethod("reduceTransparencyChanged", arguments: UIAccessibility.isReduceTransparencyEnabled)
    }
  }

  deinit {
    if let observer = transparencyObserver { NotificationCenter.default.removeObserver(observer) }
  }
}
