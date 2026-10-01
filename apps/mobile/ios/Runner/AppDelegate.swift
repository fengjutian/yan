import AVFoundation
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
    let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "YanCameraCapabilities"
    )
    let channel = FlutterMethodChannel(
      name: "yan.camera/capabilities",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "getCapabilities" {
        result(Self.cameraCapabilities())
      } else if call.method == "openAppSettings",
                let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url) { opened in result(opened) }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func cameraCapabilities() -> [String: Any] {
    let deviceTypes: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera,
      .builtInUltraWideCamera,
      .builtInTelephotoCamera,
      .builtInDualCamera,
      .builtInDualWideCamera,
      .builtInTripleCamera,
      .builtInTrueDepthCamera,
    ]
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
    var lenses = Set<String>()
    var hasFlash = false
    for device in discovery.devices {
      hasFlash = hasFlash || device.hasFlash
      switch device.deviceType {
      case .builtInUltraWideCamera: lenses.insert("ultra-wide")
      case .builtInTelephotoCamera: lenses.insert("telephoto")
      case .builtInTrueDepthCamera: lenses.insert("true-depth")
      case .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera:
        lenses.insert("multi-lens")
      default:
        lenses.insert(device.position == .front ? "front" : "wide")
      }
    }
    return [
      "platform": "ios",
      "lensTypes": Array(lenses).sorted(),
      "extensionModes": [],
      "hasFlash": hasFlash,
      "supportsMultiCamera": AVCaptureMultiCamSession.isMultiCamSupported,
    ]
  }
}
