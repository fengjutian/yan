import 'dart:io';

import 'package:ai_image_studio/features/camera/data/manual_camera_controls.dart';
import 'package:flutter/services.dart';

/// 原生专业模式返回的预览会话信息。
class ProCameraSessionInfo {
  const ProCameraSessionInfo({
    required this.textureId,
    required this.width,
    required this.height,
    required this.sensorOrientation,
    required this.minZoom,
    required this.maxZoom,
    this.supportsManual = false,
    this.minIso = 0,
    this.maxIso = 0,
    this.minShutterSeconds = 0,
    this.maxShutterSeconds = 0,
    this.minFocusDiopters = 0,
    this.maxFocusDiopters = 0,
    this.minKelvin = 2000,
    this.maxKelvin = 8000,
  });

  factory ProCameraSessionInfo.fromMap(Map<String, Object?> map) =>
      ProCameraSessionInfo(
        textureId: (map['textureId'] as num?)?.toInt() ?? 0,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        sensorOrientation: (map['sensorOrientation'] as num?)?.toInt() ?? 0,
        minZoom: (map['minZoom'] as num?)?.toDouble() ?? 1,
        maxZoom: (map['maxZoom'] as num?)?.toDouble() ?? 1,
        supportsManual: map['supportsManual'] as bool? ?? false,
        minIso: (map['minIso'] as num?)?.toDouble() ?? 0,
        maxIso: (map['maxIso'] as num?)?.toDouble() ?? 0,
        minShutterSeconds: (map['minShutterSeconds'] as num?)?.toDouble() ?? 0,
        maxShutterSeconds: (map['maxShutterSeconds'] as num?)?.toDouble() ?? 0,
        minFocusDiopters: (map['minFocusDiopters'] as num?)?.toDouble() ?? 0,
        maxFocusDiopters: (map['maxFocusDiopters'] as num?)?.toDouble() ?? 0,
        minKelvin: (map['minKelvin'] as num?)?.toDouble() ?? 2000,
        maxKelvin: (map['maxKelvin'] as num?)?.toDouble() ?? 8000,
      );

  final int textureId;
  final int width;
  final int height;
  final int sensorOrientation;
  final double minZoom;
  final double maxZoom;
  final bool supportsManual;
  final double minIso;
  final double maxIso;
  final double minShutterSeconds;
  final double maxShutterSeconds;
  final double minFocusDiopters;
  final double maxFocusDiopters;
  final double minKelvin;
  final double maxKelvin;

  double get aspectRatio => width > 0 && height > 0 ? width / height : 4 / 3;

  ManualCameraRange get manualRange => ManualCameraRange(
    minIso: minIso > 0 ? minIso : 1,
    maxIso: maxIso > minIso ? maxIso : 3200,
    minShutterSeconds: minShutterSeconds > 0 ? minShutterSeconds : 0.000125,
    maxShutterSeconds: maxShutterSeconds > minShutterSeconds
        ? maxShutterSeconds
        : 0.5,
    minKelvin: minKelvin,
    maxKelvin: maxKelvin > minKelvin ? maxKelvin : 8000,
  );
}

/// Android 原生专业模式通道。
///
/// P0 只包含打开预览、自动拍照和关闭；手动参数在 P1 接入。
class ProCameraService {
  static const _channel = MethodChannel('yan.camera/pro');

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<ProCameraSessionInfo> open({String? lensId}) async {
    final map = await _channel.invokeMapMethod<String, Object?>('open', {
      'lensId': lensId,
    });
    if (map == null) {
      throw PlatformException(code: 'pro-open', message: '原生专业模式没有返回会话信息');
    }
    return ProCameraSessionInfo.fromMap(map);
  }

  Future<Uint8List> capture() async {
    final map = await _channel.invokeMapMethod<String, Object?>('capture');
    final path = map?['path'] as String?;
    if (path == null || path.isEmpty) {
      throw PlatformException(
        code: 'capture-failed',
        message: '原生专业模式没有返回照片路径',
      );
    }
    return File(path).readAsBytes();
  }

  Future<void> setManual(ManualCameraSettings settings) async {
    await _channel.invokeMethod<void>('setManual', settings.toMap());
  }

  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // 非 Android 平台没有该通道。
    } on PlatformException {
      // 会话可能已经被生命周期释放，关闭失败不影响返回。
    }
  }
}
