import 'package:flutter/services.dart';

class CameraCapabilities {
  const CameraCapabilities({
    required this.platform,
    required this.lensTypes,
    required this.extensionModes,
    required this.hasFlash,
    required this.supportsMultiCamera,
  });

  const CameraCapabilities.fallback()
    : platform = 'unknown',
      lensTypes = const [],
      extensionModes = const [],
      hasFlash = false,
      supportsMultiCamera = false;

  final String platform;
  final List<String> lensTypes;
  final List<String> extensionModes;
  final bool hasFlash;
  final bool supportsMultiCamera;

  bool get hasAdvancedExtensions => extensionModes.isNotEmpty;
}

class CameraCapabilitiesService {
  static const _channel = MethodChannel('yan.camera/capabilities');

  Future<CameraCapabilities> load() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'getCapabilities',
      );
      if (value == null) return const CameraCapabilities.fallback();
      return CameraCapabilities(
        platform: value['platform'] as String? ?? 'unknown',
        lensTypes: _strings(value['lensTypes']),
        extensionModes: _strings(value['extensionModes']),
        hasFlash: value['hasFlash'] as bool? ?? false,
        supportsMultiCamera: value['supportsMultiCamera'] as bool? ?? false,
      );
    } on MissingPluginException {
      return const CameraCapabilities.fallback();
    } on PlatformException {
      return const CameraCapabilities.fallback();
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];
}
