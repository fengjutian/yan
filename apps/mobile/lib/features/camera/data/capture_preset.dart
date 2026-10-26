import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一次快门使用的场景参数。字段以字符串保存，
/// 避免数据层依赖相机页面的枚举定义。
class CapturePreset {
  const CapturePreset({
    required this.id,
    required this.name,
    required this.aspectRatio,
    required this.guide,
    required this.burstCount,
    required this.enhancement,
    required this.style,
    this.builtIn = false,
    this.sourceId,
    this.version = 1,
  });

  final String id;
  final String name;
  final double aspectRatio;

  /// CompositionGuide.name。
  final String guide;
  final int burstCount;

  /// CaptureEnhancement.name。
  final String enhancement;

  /// CameraStyle.name。
  final String style;
  final bool builtIn;

  /// 自定义预设复制自哪个内置预设。
  final String? sourceId;
  final int version;

  CapturePreset copyWith({
    String? id,
    String? name,
    double? aspectRatio,
    String? guide,
    int? burstCount,
    String? enhancement,
    String? style,
    bool? builtIn,
    String? sourceId,
    int? version,
  }) => CapturePreset(
    id: id ?? this.id,
    name: name ?? this.name,
    aspectRatio: aspectRatio ?? this.aspectRatio,
    guide: guide ?? this.guide,
    burstCount: burstCount ?? this.burstCount,
    enhancement: enhancement ?? this.enhancement,
    style: style ?? this.style,
    builtIn: builtIn ?? this.builtIn,
    sourceId: sourceId ?? this.sourceId,
    version: version ?? this.version,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'aspectRatio': aspectRatio,
    'guide': guide,
    'burstCount': burstCount,
    'enhancement': enhancement,
    'style': style,
    'sourceId': sourceId,
    'version': version,
  };

  factory CapturePreset.fromJson(
    Map<String, Object?> json, {
    required String fallbackId,
  }) {
    final name = json['name'];
    final rawId = json['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : fallbackId;
    return CapturePreset(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : '自定义预设',
      aspectRatio: _sanitizeAspect(json['aspectRatio']),
      guide: _pick(json['guide'], CapturePresetRepository.guides, 'thirds'),
      burstCount: json['burstCount'] == 5 ? 5 : 1,
      enhancement: _pick(
        json['enhancement'],
        CapturePresetRepository.enhancements,
        'standard',
      ),
      style: _pick(json['style'], CapturePresetRepository.styles, 'standard'),
      sourceId: json['sourceId'] is String
          ? json['sourceId'] as String
          : null,
      version: json['version'] is int && (json['version'] as int) > 0
          ? json['version'] as int
          : 1,
    );
  }

  static String _pick(Object? value, List<String> allowed, String fallback) =>
      value is String && allowed.contains(value) ? value : fallback;

  static double _sanitizeAspect(Object? value) {
    if (value is! num) return .75;
    final ratio = value.toDouble();
    for (final allowed in CapturePresetRepository.aspectRatios) {
      if ((allowed - ratio).abs() < .001) return allowed;
    }
    return .75;
  }
}

class CapturePresetCatalog {
  const CapturePresetCatalog({required this.builtIn, required this.custom});

  final List<CapturePreset> builtIn;
  final List<CapturePreset> custom;

  List<CapturePreset> get all => [...builtIn, ...custom];

  CapturePreset? byId(String? id) {
    if (id == null) return null;
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}

/// 场景预设的本地版本化存储。
///
/// - 内置预设始终来自代码，升级 App 时自动更新；
/// - 自定义预设独立保存，内置预设升级不会覆盖用户修改；
/// - 读取时对未知枚举、比例和连拍数做降级，避免旧数据导致相机崩溃。
class CapturePresetRepository {
  static const storageKey = 'camera.presets';
  static const schemaVersion = 1;

  static const aspectRatios = <double>[1, .75, .5625, 16 / 9];
  static const guides = <String>[
    'thirds',
    'center',
    'symmetry',
    'leadingLine',
    'frame',
    'goldenRatio',
  ];
  static const enhancements = <String>[
    'standard',
    'multiFrameHdr',
    'nightDenoise',
  ];
  static const styles = <String>['standard', 'vivid', 'warm', 'cool', 'mono', 'soft'];

  static const builtInPresets = <CapturePreset>[
    CapturePreset(
      id: 'builtin.portrait',
      name: '人像',
      aspectRatio: .75,
      guide: 'thirds',
      burstCount: 5,
      enhancement: 'standard',
      style: 'soft',
      builtIn: true,
    ),
    CapturePreset(
      id: 'builtin.food',
      name: '美食',
      aspectRatio: 1,
      guide: 'center',
      burstCount: 1,
      enhancement: 'multiFrameHdr',
      style: 'warm',
      builtIn: true,
    ),
    CapturePreset(
      id: 'builtin.night',
      name: '夜景',
      aspectRatio: .5625,
      guide: 'goldenRatio',
      burstCount: 1,
      enhancement: 'nightDenoise',
      style: 'cool',
      builtIn: true,
    ),
    CapturePreset(
      id: 'builtin.pet',
      name: '宠物',
      aspectRatio: .75,
      guide: 'center',
      burstCount: 5,
      enhancement: 'standard',
      style: 'vivid',
      builtIn: true,
    ),
    CapturePreset(
      id: 'builtin.shop',
      name: '探店',
      aspectRatio: .75,
      guide: 'frame',
      burstCount: 1,
      enhancement: 'multiFrameHdr',
      style: 'standard',
      builtIn: true,
    ),
    CapturePreset(
      id: 'builtin.landscape',
      name: '风景',
      aspectRatio: 16 / 9,
      guide: 'goldenRatio',
      burstCount: 1,
      enhancement: 'multiFrameHdr',
      style: 'vivid',
      builtIn: true,
    ),
  ];

  Future<CapturePresetCatalog> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    final custom = <CapturePreset>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final entries = decoded['custom'];
          if (entries is List) {
            for (var index = 0; index < entries.length; index++) {
              final item = entries[index];
              if (item is! Map) continue;
              final preset = CapturePreset.fromJson(
                item.cast<String, Object?>(),
                fallbackId: 'custom.$index',
              );
              // 内置 ID 只允许出现在代码里，防止旧数据覆盖内置预设。
              final id = preset.id.startsWith('builtin.')
                  ? 'custom.$index'
                  : preset.id;
              custom.add(preset.copyWith(id: id, builtIn: false));
            }
          }
        }
      } catch (_) {
        // 数据损坏时丢弃自定义项，保留内置预设，保证相机可用。
      }
    }
    return CapturePresetCatalog(
      builtIn: builtInPresets,
      custom: List.unmodifiable(custom),
    );
  }

  Future<void> saveCustom(List<CapturePreset> presets) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'custom': [
          for (final preset in presets) preset.copyWith(builtIn: false).toJson(),
        ],
      }),
    );
  }
}
