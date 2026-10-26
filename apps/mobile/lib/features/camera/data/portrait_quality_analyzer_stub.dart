import 'dart:typed_data';

import 'package:ai_image_studio/features/camera/data/photo_quality.dart';

/// 桌面和测试环境没有 ML Kit，人像分析直接降级为 null。
Future<PortraitQualityMetrics?> analyzePortraitQuality(Uint8List bytes) async =>
    null;
