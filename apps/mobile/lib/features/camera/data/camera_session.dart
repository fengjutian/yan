import 'package:ai_image_studio/features/camera/data/photo_metrics.dart';
import 'package:ai_image_studio/features/camera/data/photo_quality.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

class CapturedPhoto {
  const CapturedPhoto({
    required this.bytes,
    required this.score,
    this.sharpness = 0,
    this.exposure = 0,
    this.contrast = 0,
    this.clippingPenalty = 0,
    this.stability,
    this.portrait,
    this.context,
    this.reasons = const [],
  });

  final Uint8List bytes;
  final double score;
  final double sharpness;
  final double exposure;
  final double contrast;
  final double clippingPenalty;

  /// 快门触发时的稳定度分数；传感器不可用时为 null。
  final double? stability;
  final PortraitQualityMetrics? portrait;
  final CaptureContext? context;

  /// 可解释的推荐原因，如“画面清晰、全员睁眼、手持稳定”。
  final List<String> reasons;

  String get qualityLabel => PhotoQualityEvaluator.label(
    score: score,
    sharpness: sharpness,
    exposure: exposure,
    clippingPenalty: clippingPenalty,
    stability: stability,
    portrait: portrait,
  );

  String get recommendationReason =>
      reasons.isEmpty ? qualityLabel : reasons.join('、');

  PhotoQualityMetrics get metrics => PhotoQualityMetrics(
    totalScore: score,
    sharpness: sharpness,
    exposure: exposure,
    contrast: contrast,
    clippingPenalty: clippingPenalty,
    stability: stability,
    portrait: portrait,
  );

  CapturedPhoto copyWith({
    double? score,
    PortraitQualityMetrics? portrait,
    List<String>? reasons,
  }) => CapturedPhoto(
    bytes: bytes,
    score: score ?? this.score,
    sharpness: sharpness,
    exposure: exposure,
    contrast: contrast,
    clippingPenalty: clippingPenalty,
    stability: stability,
    portrait: portrait ?? this.portrait,
    context: context,
    reasons: reasons ?? this.reasons,
  );
}

class CameraSession {
  const CameraSession({this.photos = const [], this.selectedIndex = 0});
  final List<CapturedPhoto> photos;
  final int selectedIndex;
  CapturedPhoto? get selected {
    if (photos.isEmpty) return null;
    // 越界时 clamp 到 [0, photos.length - 1],避免 RangeError
    final idx = selectedIndex.clamp(0, photos.length - 1);
    return photos[idx];
  }
}

class CameraSessionController extends StateNotifier<CameraSession> {
  CameraSessionController() : super(const CameraSession());

  Future<void> setPhotos(
    List<Uint8List> values, {
    ValueChanged<double>? onProgress,
    List<CaptureContext?>? contexts,
    List<PhotoAnalysisMetrics?>? precomputedMetrics,
    PortraitAnalyzer? portraitAnalyzer,
    ValueChanged<double>? onPortraitProgress,
  }) async {
    final analyzed = <_AnalyzedPhoto>[];
    final reuseMetrics =
        precomputedMetrics != null &&
        precomputedMetrics.length == values.length &&
        precomputedMetrics.every((item) => item != null);
    if (reuseMetrics) {
      // 拍摄流程已经在裁剪/风格处理的同一个 isolate 里算过指标，
      // 这里直接复用，省掉每张照片一次全尺寸 JPEG 解码。
      for (var index = 0; index < values.length; index++) {
        analyzed.add(
          _photoWithMetrics(
            values[index],
            precomputedMetrics[index]!,
            contexts != null && index < contexts.length
                ? contexts[index]
                : null,
          ),
        );
        onProgress?.call((index + 1) / values.length);
      }
    } else {
      // 最多同时解码两张，避免高分辨率连拍触发大量 isolate 和内存峰值。
      const concurrency = 2;
      for (var offset = 0; offset < values.length; offset += concurrency) {
        final end = (offset + concurrency).clamp(0, values.length);
        final batch = await Future.wait([
          for (var index = offset; index < end; index++)
            _analyzePhoto(
              values[index],
              contexts != null && index < contexts.length
                  ? contexts[index]
                  : null,
            ),
        ]);
        analyzed.addAll(batch);
        onProgress?.call(analyzed.length / values.length);
      }
    }
    analyzed.sort((a, b) => b.score.compareTo(a.score));
    final unique = <_AnalyzedPhoto>[];
    final signatures = <PhotoAnalysisMetrics>[];
    for (final item in analyzed) {
      final metrics = item.metrics;
      final duplicate = signatures.any(
        (existing) =>
            _hammingDistance(existing.hash, metrics.hash) <= 2 &&
            (existing.averageLuminance - metrics.averageLuminance).abs() < 8,
      );
      if (!duplicate) {
        unique.add(item);
        signatures.add(metrics);
      }
    }
    var photos = [for (final item in unique) _buildPhoto(item, portrait: null)];
    if (portraitAnalyzer != null && photos.isNotEmpty) {
      photos = await _mergePortraitMetrics(
        photos,
        portraitAnalyzer,
        onProgress: onPortraitProgress,
      );
    }
    state = CameraSession(photos: photos);
  }

  Future<_AnalyzedPhoto> _analyzePhoto(
    Uint8List bytes,
    CaptureContext? context,
  ) async {
    final metrics = await compute(_analyzeIsolate, bytes);
    return _photoWithMetrics(bytes, metrics, context);
  }

  _AnalyzedPhoto _photoWithMetrics(
    Uint8List bytes,
    PhotoAnalysisMetrics metrics,
    CaptureContext? context,
  ) {
    final stability = context?.stabilityScore;
    return _AnalyzedPhoto(
      bytes: bytes,
      metrics: metrics,
      context: context,
      score: PhotoQualityEvaluator.applyStability(metrics.score, stability),
    );
  }

  Future<List<CapturedPhoto>> _mergePortraitMetrics(
    List<CapturedPhoto> photos,
    PortraitAnalyzer analyzer, {
    ValueChanged<double>? onProgress,
  }) async {
    final merged = <CapturedPhoto>[];
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      PortraitQualityMetrics? portrait;
      try {
        portrait = await analyzer(photo.bytes);
      } catch (_) {
        // 检测失败时保留通用评分，人像能力单独降级，不影响选片主流程。
        portrait = null;
      }
      if (portrait != null && portrait.hasFaces) {
        final score = PhotoQualityEvaluator.mergePortrait(
          photo.score,
          portrait,
        );
        merged.add(
          _buildPhoto(
            _AnalyzedPhoto(
              bytes: photo.bytes,
              metrics: PhotoAnalysisMetrics(
                score: photo.score,
                sharpness: photo.sharpness,
                exposure: photo.exposure,
                contrast: photo.contrast,
                clippingPenalty: photo.clippingPenalty,
                averageLuminance: 0,
                hash: 0,
              ),
              context: photo.context,
              score: score,
            ),
            portrait: portrait,
          ),
        );
      } else {
        merged.add(photo);
      }
      onProgress?.call((index + 1) / photos.length);
    }
    merged.sort((a, b) => b.score.compareTo(a.score));
    return merged;
  }

  CapturedPhoto _buildPhoto(
    _AnalyzedPhoto item, {
    required PortraitQualityMetrics? portrait,
  }) {
    final metrics = item.metrics;
    final stability = item.context?.stabilityScore;
    return CapturedPhoto(
      bytes: item.bytes,
      score: item.score,
      sharpness: metrics.sharpness,
      exposure: metrics.exposure,
      contrast: metrics.contrast,
      clippingPenalty: metrics.clippingPenalty,
      stability: stability,
      portrait: portrait,
      context: item.context,
      reasons: PhotoQualityEvaluator.describe(
        sharpness: metrics.sharpness,
        exposure: metrics.exposure,
        contrast: metrics.contrast,
        clippingPenalty: metrics.clippingPenalty,
        stability: stability,
        portrait: portrait,
      ),
    );
  }

  void select(int index) {
    final clamped = state.photos.isEmpty
        ? 0
        : index.clamp(0, state.photos.length - 1);
    state = CameraSession(photos: state.photos, selectedIndex: clamped);
  }

  void clear() => state = const CameraSession();
}

class _AnalyzedPhoto {
  const _AnalyzedPhoto({
    required this.bytes,
    required this.metrics,
    required this.score,
    this.context,
  });
  final Uint8List bytes;
  final PhotoAnalysisMetrics metrics;
  final double score;
  final CaptureContext? context;
}

/// 必须是顶层函数才能用 compute() 丢到 isolate。
///
/// 拍摄流程会通过 [setPhotos] 的 precomputedMetrics 直接复用指标；
/// 只有相册导入等没有预计算的路径才需要在这里解码。
PhotoAnalysisMetrics _analyzeIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return PhotoAnalysisMetrics.unavailable;
  return analyzePhotoMetrics(decoded);
}

int _hammingDistance(int left, int right) {
  var value = left ^ right;
  var count = 0;
  for (var index = 0; index < 64; index++) {
    count += value & 1;
    value >>= 1;
  }
  return count;
}

final cameraSessionProvider =
    StateNotifierProvider<CameraSessionController, CameraSession>(
      (ref) => CameraSessionController(),
    );
