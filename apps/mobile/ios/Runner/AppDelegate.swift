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
    var lensDetails = [[String: Any]]()
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
      let type: String
      let nominalZoom: Double
      switch device.deviceType {
      case .builtInUltraWideCamera:
        type = "ultra-wide"; nominalZoom = 0.5
      case .builtInTelephotoCamera:
        type = "telephoto"; nominalZoom = 3.0
      case .builtInTrueDepthCamera:
        type = "true-depth"; nominalZoom = 1.0
      case .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera:
        type = "multi-lens"; nominalZoom = 1.0
      default:
        type = device.position == .front ? "front" : "wide"
        nominalZoom = 1.0
      }
      var minimumFocusDistance = 0.0
      if #available(iOS 15.0, *) {
        minimumFocusDistance = Double(device.minimumFocusDistance)
      }
      lensDetails.append([
        "id": device.uniqueID,
        "facing": device.position == .front ? "front" : "back",
        "type": type,
        "focalLengths": [],
        "minIso": Double(device.activeFormat.minISO),
        "maxIso": Double(device.activeFormat.maxISO),
        "minExposureSeconds": CMTimeGetSeconds(device.activeFormat.minExposureDuration),
        "maxExposureSeconds": CMTimeGetSeconds(device.activeFormat.maxExposureDuration),
        "minimumFocusDistance": minimumFocusDistance,
        "nominalZoom": nominalZoom,
        "supportsRaw": false,
      ])
    }
    return [
      "platform": "ios",
      "lensTypes": Array(lenses).sorted(),
      "extensionModes": [],
      "hasFlash": hasFlash,
      "supportsMultiCamera": AVCaptureMultiCamSession.isMultiCamSupported,
      "lenses": lensDetails,
    ]
  }
}
