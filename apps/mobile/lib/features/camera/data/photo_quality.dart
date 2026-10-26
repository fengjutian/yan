import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// 一次快门对应的拍摄上下文，随照片一起保存，让质量评分可解释、可回归。
class CaptureContext {
  const CaptureContext({
    required this.cameraId,
    required this.lensType,
    required this.zoom,
    required this.exposureOffset,
    required this.capturedAt,
    this.stabilityScore,
    this.presetId,
  });

  final String cameraId;
  final String lensType;
  final double zoom;
  final double exposureOffset;

  /// 快门触发时的稳定度分数；传感器不可用时为 null。
  final double? stabilityScore;
  final String? presetId;
  final DateTime capturedAt;

  CaptureContext copyWith({double? stabilityScore, String? presetId}) =>
      CaptureContext(
        cameraId: cameraId,
        lensType: lensType,
        zoom: zoom,
        exposureOffset: exposureOffset,
        capturedAt: capturedAt,
        stabilityScore: stabilityScore ?? this.stabilityScore,
        presetId: presetId ?? this.presetId,
      );
}

/// 人像照片的专项质量指标。
class PortraitQualityMetrics {
  const PortraitQualityMetrics({
    required this.faceCount,
    required this.faceSharpness,
    required this.eyesOpenScore,
    required this.smileScore,
    required this.occlusionRisk,
  });

  final int faceCount;

  /// 主体人脸区域的清晰度，0～100。
  final double faceSharpness;

  /// 全员睁眼概率，取所有人脸中最低的睁眼分数，0～100。
  final double eyesOpenScore;

  /// 笑容概率，0～100。
  final double smileScore;

  /// 遮挡风险，0～100，越低越好。
  final double occlusionRisk;

  bool get hasFaces => faceCount > 0;

  double get expressionScore =>
      (smileScore * .6 + (100 - occlusionRisk) * .4).clamp(0, 100).toDouble();
}

/// 与照片一起写入本地元数据的完整质量指标。
class PhotoQualityMetrics {
  const PhotoQualityMetrics({
    required this.totalScore,
    required this.sharpness,
    required this.exposure,
    required this.contrast,
    required this.clippingPenalty,
    this.stability,
    this.portrait,
  });

  final double totalScore;
  final double sharpness;
  final double exposure;
  final double contrast;
  final double clippingPenalty;
  final double? stability;
  final PortraitQualityMetrics? portrait;
}

/// 人像分析的注入点：真机使用 ML Kit，测试或桌面平台可返回 null。
typedef PortraitAnalyzer =
    Future<PortraitQualityMetrics?> Function(Uint8List bytes);

/// 质量评分的纯函数集合，与相机、插件和平台通道解耦，便于单元测试。
class PhotoQualityEvaluator {
  const PhotoQualityEvaluator._();

  /// 手抖惩罚上限，保证稳定度只是排序因素，不会压过严重失焦或过曝。
  static const double maxStabilityPenalty = 16;

  /// 手抖惩罚：相同画质下，晃动更少的照片排得更靠前。
  static double applyStability(double genericScore, double? stability) {
    if (stability == null) return genericScore.clamp(0, 100).toDouble();
    final penalty = (100 - stability.clamp(0, 100)) / 100 * maxStabilityPenalty;
    return (genericScore - penalty).clamp(0, 100).toDouble();
  }

  /// 人像照片的合并评分：通用画质 55%，人脸清晰度 20%，
  /// 睁眼状态 15%，表情与遮挡 10%。没有人物时保持通用评分不变。
  static double mergePortrait(
    double genericScore,
    PortraitQualityMetrics? portrait,
  ) {
    if (portrait == null || !portrait.hasFaces) {
      return genericScore.clamp(0, 100).toDouble();
    }
    final score =
        genericScore.clamp(0, 100) * .55 +
        portrait.faceSharpness.clamp(0, 100) * .20 +
        portrait.eyesOpenScore.clamp(0, 100) * .15 +
        portrait.expressionScore * .10;
    return score.clamp(0, 100).toDouble();
  }

  /// 面向用户的简短质量原因，按重要性截断，避免预览页文字过长。
  static List<String> describe({
    required double sharpness,
    required double exposure,
    required double contrast,
    required double clippingPenalty,
    double? stability,
    PortraitQualityMetrics? portrait,
  }) {
    final reasons = <String>[];
    if (portrait != null && portrait.hasFaces) {
      reasons.add(portrait.faceSharpness >= 60 ? '人物清晰' : '人脸稍糊');
      reasons.add(
        portrait.eyesOpenScore >= 70
            ? (portrait.faceCount > 1 ? '全员睁眼' : '人物睁眼')
            : '有人闭眼',
      );
      if (portrait.smileScore >= 55) reasons.add('表情自然');
      if (portrait.occlusionRisk >= 45) reasons.add('人物有遮挡');
    }
    if (sharpness >= 60) {
      reasons.add('画面清晰');
    } else if (sharpness < 25) {
      reasons.add('轻微模糊');
    }
    if (exposure >= 60) {
      reasons.add('曝光准确');
    } else if (exposure < 45) {
      reasons.add('曝光待改善');
    }
    if (clippingPenalty > 18) reasons.add('明暗细节较少');
    if (stability != null) {
      if (stability >= 80) {
        reasons.add('手持稳定');
      } else if (stability < 55) {
        reasons.add('手抖偏多');
      }
    }
    return reasons.take(3).toList(growable: false);
  }

  static String label({
    required double score,
    required double sharpness,
    required double exposure,
    required double clippingPenalty,
    double? stability,
    PortraitQualityMetrics? portrait,
  }) {
    if (portrait != null && portrait.hasFaces && portrait.eyesOpenScore < 35) {
      return '有人闭眼';
    }
    if (stability != null && stability < 50) return '手抖偏多';
    if (sharpness < 25) return '轻微模糊';
    if (exposure < 45) return '曝光待改善';
    if (clippingPenalty > 18) return '明暗细节较少';
    if (score >= 78) return '优质';
    return '可用';
  }
}
