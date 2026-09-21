import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

class CapturedPhoto {
  const CapturedPhoto({required this.bytes, required this.score});
  final Uint8List bytes;
  final double score;
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

  Future<void> setPhotos(List<Uint8List> values) async {
    // 评分丢到后台 isolate,5 张连拍不再卡 UI 线程
    final scored = await Future.wait(
      values.map((bytes) async => CapturedPhoto(
            bytes: bytes,
            score: await compute(_scoreIsolate, bytes),
          )),
    );
    scored.sort((a, b) => b.score.compareTo(a.score));
    state = CameraSession(photos: scored);
  }

  void select(int index) {
    final clamped = state.photos.isEmpty
        ? 0
        : index.clamp(0, state.photos.length - 1);
    state = CameraSession(photos: state.photos, selectedIndex: clamped);
  }

  void clear() => state = const CameraSession();
}

/// 必须顶层函数才能用 compute() 丢到 isolate
double _scoreIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return 0;
  final image = img.copyResize(decoded, width: 120);
  var luminance = 0.0;
  var edges = 0.0;
  var count = 0;
  for (var y = 1; y < image.height - 1; y += 2) {
    for (var x = 1; x < image.width - 1; x += 2) {
      double gray(img.Pixel p) => .299 * p.r + .587 * p.g + .114 * p.b;
      final center = gray(image.getPixel(x, y));
      luminance += center;
      edges += (center - gray(image.getPixel(x + 1, y))).abs();
      edges += (center - gray(image.getPixel(x, y + 1))).abs();
      count++;
    }
  }
  if (count == 0) return 0;
  final light = luminance / count;
  final exposureScore = (1 - (light - 135).abs() / 135).clamp(0.0, 1.0);
  return (edges / count * .7 + exposureScore * 30).clamp(0, 100).toDouble();
}

final cameraSessionProvider =
    StateNotifierProvider<CameraSessionController, CameraSession>(
        (ref) => CameraSessionController());
