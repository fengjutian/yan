import 'dart:math' as math;

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
  });
  final Uint8List bytes;
  final double score;
  final double sharpness;
  final double exposure;
  final double contrast;
  final double clippingPenalty;

  String get qualityLabel {
    if (sharpness < 25) return '轻微模糊';
    if (exposure < 45) return '曝光待改善';
    if (clippingPenalty > 18) return '明暗细节较少';
    if (score >= 78) return '优质';
    return '可用';
  }
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
  }) async {
    // 最多同时解码两张，避免高分辨率连拍触发大量 isolate 和内存峰值。
    final analyzed = <_AnalyzedPhoto>[];
    const concurrency = 2;
    for (var offset = 0; offset < values.length; offset += concurrency) {
      final end = (offset + concurrency).clamp(0, values.length);
      final batch = await Future.wait(
        values.sublist(offset, end).map((bytes) async {
          final result = await compute(_analyzeIsolate, bytes);
          return _AnalyzedPhoto(bytes: bytes, metrics: result);
        }),
      );
      analyzed.addAll(batch);
      onProgress?.call(analyzed.length / values.length);
    }
    analyzed.sort((a, b) => b.metrics.score.compareTo(a.metrics.score));
    final unique = <CapturedPhoto>[];
    final signatures = <_PhotoMetrics>[];
    for (final item in analyzed) {
      final metrics = item.metrics;
      final duplicate = signatures.any(
        (existing) =>
            _hammingDistance(existing.hash, metrics.hash) <= 2 &&
            (existing.averageLuminance - metrics.averageLuminance).abs() < 8,
      );
      if (!duplicate) {
        unique.add(
          CapturedPhoto(
            bytes: item.bytes,
            score: metrics.score,
            sharpness: metrics.sharpness,
            exposure: metrics.exposure,
            contrast: metrics.contrast,
            clippingPenalty: metrics.clippingPenalty,
          ),
        );
        signatures.add(metrics);
      }
    }
    state = CameraSession(photos: unique);
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
  const _AnalyzedPhoto({required this.bytes, required this.metrics});
  final Uint8List bytes;
  final _PhotoMetrics metrics;
}

class _PhotoMetrics {
  const _PhotoMetrics({
    required this.score,
    required this.sharpness,
    required this.exposure,
    required this.contrast,
    required this.clippingPenalty,
    required this.averageLuminance,
    required this.hash,
  });
  final double score;
  final double sharpness;
  final double exposure;
  final double contrast;
  final double clippingPenalty;
  final double averageLuminance;
  final int hash;
}

/// 必须是顶层函数才能用 compute() 丢到 isolate。
_PhotoMetrics _analyzeIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return const _PhotoMetrics(
      score: 0,
      sharpness: 0,
      exposure: 0,
      contrast: 0,
      clippingPenalty: 100,
      averageLuminance: 0,
      hash: 0,
    );
  }
  final image = img.copyResize(decoded, width: 120);
  var luminance = 0.0;
  var squaredLuminance = 0.0;
  var edges = 0.0;
  var clippedHighlights = 0;
  var clippedShadows = 0;
  var count = 0;
  for (var y = 1; y < image.height - 1; y += 2) {
    for (var x = 1; x < image.width - 1; x += 2) {
      double gray(img.Pixel p) => .299 * p.r + .587 * p.g + .114 * p.b;
      final center = gray(image.getPixel(x, y));
      luminance += center;
      squaredLuminance += center * center;
      edges += (center - gray(image.getPixel(x + 1, y))).abs();
      edges += (center - gray(image.getPixel(x, y + 1))).abs();
      if (center >= 248) clippedHighlights++;
      if (center <= 7) clippedShadows++;
      count++;
    }
  }
  if (count == 0) {
    return const _PhotoMetrics(
      score: 0,
      sharpness: 0,
      exposure: 0,
      contrast: 0,
      clippingPenalty: 100,
      averageLuminance: 0,
      hash: 0,
    );
  }
  final light = luminance / count;
  final variance = math.max(0, squaredLuminance / count - light * light);
  final sharpness = (edges / count * 2.2).clamp(0, 100).toDouble();
  final exposure = ((1 - (light - 135).abs() / 135) * 100)
      .clamp(0, 100)
      .toDouble();
  final contrast = (math.sqrt(variance) * 2.4).clamp(0, 100).toDouble();
  final clippingPenalty = ((clippedHighlights + clippedShadows) / count * 100)
      .clamp(0, 100)
      .toDouble();
  final score =
      (sharpness * .48 +
              exposure * .30 +
              contrast * .22 -
              clippingPenalty * .35)
          .clamp(0, 100)
          .toDouble();
  return _PhotoMetrics(
    score: score,
    sharpness: sharpness,
    exposure: exposure,
    contrast: contrast,
    clippingPenalty: clippingPenalty,
    averageLuminance: light,
    hash: _averageHash(decoded),
  );
}

int _averageHash(img.Image source) {
  final tiny = img.copyResize(source, width: 8, height: 8);
  final values = <double>[];
  for (final pixel in tiny) {
    values.add(.299 * pixel.r + .587 * pixel.g + .114 * pixel.b);
  }
  final average = values.fold<double>(0, (sum, value) => sum + value) / 64;
  var hash = 0;
  for (var index = 0; index < values.length; index++) {
    if (values[index] >= average) hash |= 1 << index;
  }
  return hash;
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
