import 'package:ai_image_studio/features/camera/data/camera_capabilities.dart';
import 'package:flutter/services.dart';

/// 相机专业参数的运行模式。
enum ManualCameraMode {
  /// 曝光、白平衡和对焦全部自动。
  auto,

  /// 曝光自动，白平衡和对焦锁定。
  semi,

  /// ISO、快门、白平衡和对焦全部手动。
  manual,
}

/// 当前物理镜头允许的手动参数范围。所有值都来自原生能力检测。
class ManualCameraRange {
  const ManualCameraRange({
    required this.minIso,
    required this.maxIso,
    required this.minShutterSeconds,
    required this.maxShutterSeconds,
    required this.minKelvin,
    required this.maxKelvin,
  });

  factory ManualCameraRange.fromLens(NativeCameraLens lens) {
    final minShutter = lens.minExposureSeconds > 0
        ? lens.minExposureSeconds
        : 1 / 8000;
    final maxShutter = lens.maxExposureSeconds > minShutter
        ? lens.maxExposureSeconds
        : 1 / 2;
    return ManualCameraRange(
      minIso: lens.minIso > 0 ? lens.minIso : 1,
      maxIso: lens.maxIso > lens.minIso ? lens.maxIso : 3200,
      minShutterSeconds: minShutter,
      maxShutterSeconds: maxShutter,
      minKelvin: lens.minKelvin,
      maxKelvin: lens.maxKelvin > lens.minKelvin ? lens.maxKelvin : 8000,
    );
  }

  final double minIso;
  final double maxIso;
  final double minShutterSeconds;
  final double maxShutterSeconds;
  final double minKelvin;
  final double maxKelvin;

  bool get isUsable =>
      maxIso > minIso &&
      maxShutterSeconds > minShutterSeconds &&
      maxKelvin > minKelvin;

  double clampIso(double value) => value.clamp(minIso, maxIso).toDouble();

  double clampShutter(double value) =>
      value.clamp(minShutterSeconds, maxShutterSeconds).toDouble();

  double clampKelvin(double value) =>
      value.clamp(minKelvin, maxKelvin).toDouble();

  double clampFocus(double value) => value.clamp(0.0, 1.0).toDouble();
}

/// 一次专业参数设置。auto 模式下其余值只是 UI 记忆值，不会下发。
class ManualCameraSettings {
  const ManualCameraSettings({
    required this.mode,
    required this.iso,
    required this.shutterSeconds,
    required this.kelvin,
    required this.focus,
  });

  static const auto = ManualCameraSettings(
    mode: ManualCameraMode.auto,
    iso: 100,
    shutterSeconds: 1 / 60,
    kelvin: 5200,
    focus: 0.5,
  );

  final ManualCameraMode mode;
  final double iso;
  final double shutterSeconds;
  final double kelvin;
  final double focus;

  ManualCameraSettings copyWith({
    ManualCameraMode? mode,
    double? iso,
    double? shutterSeconds,
    double? kelvin,
    double? focus,
  }) => ManualCameraSettings(
    mode: mode ?? this.mode,
    iso: iso ?? this.iso,
    shutterSeconds: shutterSeconds ?? this.shutterSeconds,
    kelvin: kelvin ?? this.kelvin,
    focus: focus ?? this.focus,
  );

  /// 把值限制在当前镜头的硬件范围内，避免下发非法参数。
  ManualCameraSettings clamped(ManualCameraRange range) => ManualCameraSettings(
    mode: mode,
    iso: range.clampIso(iso),
    shutterSeconds: range.clampShutter(shutterSeconds),
    kelvin: range.clampKelvin(kelvin),
    focus: range.clampFocus(focus),
  );

  Map<String, Object?> toMap() => {
    'mode': mode.name,
    'iso': iso,
    'shutterSeconds': shutterSeconds,
    'kelvin': kelvin,
    'focus': focus,
  };
}

/// 专业参数的原生通道：iOS 用 AVFoundation，Android 目前由能力检测报告不支持。
class ManualCameraControlService {
  static const _channel = MethodChannel('yan.camera/manual');

  Future<void> apply(String deviceId, ManualCameraSettings settings) async {
    if (settings.mode == ManualCameraMode.auto) {
      await reset(deviceId);
      return;
    }
    await _channel.invokeMethod<void>('apply', {
      'deviceId': deviceId,
      ...settings.toMap(),
    });
  }

  Future<void> reset(String deviceId) async {
    await _channel.invokeMethod<void>('reset', {'deviceId': deviceId});
  }
}
