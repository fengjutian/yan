import AVFoundation
import Flutter
import os
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
      } else if call.method == "getDiagnostics" {
        result(Self.deviceDiagnostics())
      } else if call.method == "openAppSettings",
                let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url) { opened in result(opened) }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let manualChannel = FlutterMethodChannel(
      name: "yan.camera/manual",
      binaryMessenger: registrar.messenger()
    )
    manualChannel.setMethodCallHandler { call, result in
      if call.method == "apply" || call.method == "reset" {
        Self.handleManualControls(
          call.method,
          arguments: call.arguments,
          result: result
        )
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func deviceDiagnostics() -> [String: Any] {
    var result: [String: Any] = [:]
    let url = URL(fileURLWithPath: NSHomeDirectory())
    if let values = try? url.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey,
      .volumeTotalCapacityKey,
    ]) {
      if let free = values.volumeAvailableCapacityForImportantUsage {
        result["freeStorageMb"] = Int(free / 1_048_576)
      }
      if let total = values.volumeTotalCapacity {
        result["totalStorageMb"] = total / 1_048_576
      }
    }

    var availableMemoryMb: Int?
    if #available(iOS 13.0, *) {
      availableMemoryMb = Int(os_proc_available_memory()) / 1_048_576
      result["availableMemoryMb"] = availableMemoryMb
    }
    result["lowMemory"] = (availableMemoryMb ?? 9999) < 300

    let thermal: String
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: thermal = "nominal"
    case .fair: thermal = "fair"
    case .serious: thermal = "serious"
    case .critical: thermal = "critical"
    @unknown default: thermal = "unknown"
    }
    result["thermalStatus"] = thermal
    return result
  }

  private struct ManualControlError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  private static let manualQueue = DispatchQueue(label: "yan.camera.manual")

  private static func handleManualControls(
    _ method: String,
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let args = arguments as? [String: Any],
          let deviceId = args["deviceId"] as? String,
          let device = AVCaptureDevice(uniqueID: deviceId) else {
      result(
        FlutterError(
          code: "manual-controls",
          message: "找不到当前镜头",
          details: nil
        )
      )
      return
    }
    let mode = args["mode"] as? String ?? "manual"
    manualQueue.async {
      do {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if method == "reset" || mode == "auto" {
          resetManualControls(device)
        } else {
          try applyManualControls(device, mode: mode, args: args)
        }
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "manual-controls",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private static func resetManualControls(_ device: AVCaptureDevice) {
    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }
    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
      device.whiteBalanceMode = .continuousAutoWhiteBalance
    }
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
  }

  private static func applyManualControls(
    _ device: AVCaptureDevice,
    mode: String,
    args: [String: Any]
  ) throws {
    let iso = args["iso"] as? Double ?? Double(device.activeFormat.minISO)
    let shutter = args["shutterSeconds"] as? Double ?? 1.0 / 60.0
    let kelvin = args["kelvin"] as? Double ?? 5200
    let focus = args["focus"] as? Double ?? 0.5

    if mode == "manual" {
      guard device.isExposureModeSupported(.custom) else {
        throw ManualControlError(message: "当前镜头不支持手动曝光")
      }
      let format = device.activeFormat
      let clampedIso = min(max(Float(iso), format.minISO), format.maxISO)
      let minSeconds = CMTimeGetSeconds(format.minExposureDuration)
      let maxSeconds = CMTimeGetSeconds(format.maxExposureDuration)
      let safeShutter = min(max(shutter, minSeconds), maxSeconds)
      let duration = CMTime(
        seconds: safeShutter,
        preferredTimescale: 1_000_000_000
      )
      device.setExposureModeCustom(
        duration: duration,
        iso: clampedIso,
        completionHandler: nil
      )
    } else if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }

    if device.isWhiteBalanceModeSupported(.locked) {
      let temperature = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
        temperature: Float(min(max(kelvin, 2000), 8000)),
        tint: 0
      )
      var gains = device.deviceWhiteBalanceGains(for: temperature)
      let maxGain = device.maxWhiteBalanceGain
      gains.redGain = min(max(gains.redGain, 1.0), maxGain)
      gains.greenGain = min(max(gains.greenGain, 1.0), maxGain)
      gains.blueGain = min(max(gains.blueGain, 1.0), maxGain)
      device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
    }

    if device.isFocusModeSupported(.locked) {
      let position = Float(min(max(focus, 0.0), 1.0))
      device.setFocusModeLocked(
        lensPosition: position,
        completionHandler: nil
      )
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
        "supportsManualControls": device.isExposureModeSupported(.custom)
          && device.isWhiteBalanceModeSupported(.locked)
          && device.isFocusModeSupported(.locked),
        "minKelvin": 2000,
        "maxKelvin": 8000,
        "manualUnavailableReason": device.isExposureModeSupported(.custom)
          && device.isWhiteBalanceModeSupported(.locked)
          && device.isFocusModeSupported(.locked)
          ? ""
          : "当前镜头不支持手动曝光、白平衡或对焦",
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
