import 'package:ai_image_studio/features/camera/data/camera_diagnostics.dart';
import 'package:flutter/services.dart';

class CameraCapabilities {
  const CameraCapabilities({
    required this.platform,
    required this.lensTypes,
    required this.extensionModes,
    required this.hasFlash,
    required this.supportsMultiCamera,
    this.lenses = const [],
  });

  const CameraCapabilities.fallback()
    : platform = 'unknown',
      lensTypes = const [],
      extensionModes = const [],
      hasFlash = false,
      supportsMultiCamera = false,
      lenses = const [];

  final String platform;
  final List<String> lensTypes;
  final List<String> extensionModes;
  final bool hasFlash;
  final bool supportsMultiCamera;
  final List<NativeCameraLens> lenses;

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
        lenses: _maps(
          value['lenses'],
        ).map(NativeCameraLens.fromMap).toList(growable: false),
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

  /// 读取剩余存储、可用内存和设备温度；原生未实现时安全回退为空数据。
  Future<DeviceDiagnostics> loadDiagnostics() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'getDiagnostics',
      );
      if (value == null) return const DeviceDiagnostics();
      int? number(Object? item) => item is num
          ? item.round()
          : (item is String ? int.tryParse(item) : null);
      return DeviceDiagnostics(
        freeStorageMb: number(value['freeStorageMb']),
        totalStorageMb: number(value['totalStorageMb']),
        availableMemoryMb: number(value['availableMemoryMb']),
        totalMemoryMb: number(value['totalMemoryMb']),
        lowMemory: value['lowMemory'] as bool? ?? false,
        thermalStatus: value['thermalStatus'] as String?,
      );
    } on MissingPluginException {
      return const DeviceDiagnostics();
    } on PlatformException {
      return const DeviceDiagnostics();
    }
  }

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  static Iterable<Map<String, Object?>> _maps(Object? value) sync* {
    if (value is! List) return;
    for (final item in value) {
      if (item is Map) yield item.cast<String, Object?>();
    }
  }
}

class NativeCameraLens {
  const NativeCameraLens({
    required this.id,
    required this.facing,
    required this.type,
    required this.focalLengths,
    required this.minIso,
    required this.maxIso,
    required this.minExposureSeconds,
    required this.maxExposureSeconds,
    required this.minimumFocusDistance,
    required this.nominalZoom,
    required this.supportsRaw,
    this.supportsManualControls = false,
    this.minKelvin = 2000,
    this.maxKelvin = 8000,
    this.manualUnavailableReason,
  });

  factory NativeCameraLens.fromMap(Map<String, Object?> value) =>
      NativeCameraLens(
        id: value['id'] as String? ?? '',
        facing: value['facing'] as String? ?? 'unknown',
        type: value['type'] as String? ?? 'unknown',
        focalLengths: _numbers(value['focalLengths']),
        minIso: _number(value['minIso']),
        maxIso: _number(value['maxIso']),
        minExposureSeconds: _number(value['minExposureSeconds']),
        maxExposureSeconds: _number(value['maxExposureSeconds']),
        minimumFocusDistance: _number(value['minimumFocusDistance']),
        nominalZoom: _number(value['nominalZoom'], fallback: 1),
        supportsRaw: value['supportsRaw'] as bool? ?? false,
        supportsManualControls:
            value['supportsManualControls'] as bool? ?? false,
        minKelvin: _number(value['minKelvin'], fallback: 2000),
        maxKelvin: _number(value['maxKelvin'], fallback: 8000),
        manualUnavailableReason: value['manualUnavailableReason'] as String?,
      );

  final String id;
  final String facing;
  final String type;
  final List<double> focalLengths;
  final double minIso;
  final double maxIso;
  final double minExposureSeconds;
  final double maxExposureSeconds;
  final double minimumFocusDistance;
  final double nominalZoom;
  final bool supportsRaw;

  /// 当前原生实现是否可以真正下发 ISO/快门/白平衡/对焦。
  final bool supportsManualControls;
  final double minKelvin;
  final double maxKelvin;

  /// 不支持时给用户看的原因。
  final String? manualUnavailableReason;

  bool get isBack => facing == 'back';
  bool get supportsManualFocus => minimumFocusDistance > 0;

  static double _number(Object? value, {double fallback = 0}) =>
      value is num ? value.toDouble() : fallback;

  static List<double> _numbers(Object? value) => value is List
      ? value.whereType<num>().map((item) => item.toDouble()).toList()
      : const [];
}
