import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 平台分享尺寸预设(对应 PRD 5.4)。
enum SharePlatform {
  original('原始尺寸'),
  square('1:1 小红书/朋友圈'),
  portrait3x4('3:4 朋友圈'),
  portrait4x5('4:5 Instagram'),
  story9x16('9:16 抖音/小红书 Story');

  const SharePlatform(this.label);
  final String label;
}

/// 分享用的水印位置。
enum WatermarkPosition { hidden, bottomLeft, bottomRight, center }

@immutable
class ShareConfig {
  const ShareConfig({
    this.platform = SharePlatform.square,
    this.watermark = WatermarkPosition.bottomLeft,
    this.showMetadata = true,
  });

  final SharePlatform platform;
  final WatermarkPosition watermark;

  /// 分享图片里是否保留 EXIF 位置/设备信息。
  final bool showMetadata;

  ShareConfig copyWith({
    SharePlatform? platform,
    WatermarkPosition? watermark,
    bool? showMetadata,
  }) =>
      ShareConfig(
        platform: platform ?? this.platform,
        watermark: watermark ?? this.watermark,
        showMetadata: showMetadata ?? this.showMetadata,
      );
}

@immutable
class ShareDraft {
  const ShareDraft({
    required this.imageUrl,
    required this.caption,
    required this.tags,
    required this.config,
  });

  final String imageUrl;
  final String caption;
  final List<String> tags;
  final ShareConfig config;

  ShareDraft copyWith({
    String? imageUrl,
    String? caption,
    List<String>? tags,
    ShareConfig? config,
  }) =>
      ShareDraft(
        imageUrl: imageUrl ?? this.imageUrl,
        caption: caption ?? this.caption,
        tags: tags ?? this.tags,
        config: config ?? this.config,
      );
}

final shareConfigProvider =
    StateProvider<ShareConfig>((ref) => const ShareConfig());
