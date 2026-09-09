import 'dart:typed_data';

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
  CapturedPhoto? get selected => photos.isEmpty ? null : photos[selectedIndex];
}

class CameraSessionController extends StateNotifier<CameraSession> {
  CameraSessionController() : super(const CameraSession());

  Future<void> setPhotos(List<Uint8List> values) async {
    final photos = values.map((bytes) => CapturedPhoto(bytes: bytes, score: _score(bytes))).toList();
    photos.sort((a, b) => b.score.compareTo(a.score));
    state = CameraSession(photos: photos);
  }

  void select(int index) => state = CameraSession(photos: state.photos, selectedIndex: index);
  void clear() => state = const CameraSession();

  double _score(Uint8List bytes) {
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
}

final cameraSessionProvider = StateNotifierProvider<CameraSessionController, CameraSession>((ref) => CameraSessionController());
