import 'dart:io';
import 'dart:typed_data';

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
  });

  factory ProCameraSessionInfo.fromMap(Map<String, Object?> map) =>
      ProCameraSessionInfo(
        textureId: (map['textureId'] as num?)?.toInt() ?? 0,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        sensorOrientation: (map['sensorOrientation'] as num?)?.toInt() ?? 0,
        minZoom: (map['minZoom'] as num?)?.toDouble() ?? 1,
        maxZoom: (map['maxZoom'] as num?)?.toDouble() ?? 1,
      );

  final int textureId;
  final int width;
  final int height;
  final int sensorOrientation;
  final double minZoom;
  final double maxZoom;

  double get aspectRatio => width > 0 && height > 0 ? width / height : 4 / 3;
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
