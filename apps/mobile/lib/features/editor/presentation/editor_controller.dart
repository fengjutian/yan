import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

/// 编辑器状态。
@immutable
class EditorState {
  const EditorState({
    required this.sourceBytes,
    this.brightness = 0, // -100..100
    this.contrast = 0,   // -100..100
    this.saturation = 0, // -100..100
    this.rotationQuarterTurns = 0, // 0..3
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropRect, // normalized 0..1
  });

  final Uint8List sourceBytes;
  final int brightness;
  final int contrast;
  final int saturation;
  final int rotationQuarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final CropRectNormalized? cropRect;

  EditorState copyWith({
    int? brightness,
    int? contrast,
    int? saturation,
    int? rotationQuarterTurns,
    bool? flipHorizontal,
    bool? flipVertical,
    CropRectNormalized? cropRect,
    bool clearCrop = false,
  }) =>
      EditorState(
        sourceBytes: sourceBytes,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        rotationQuarterTurns:
            rotationQuarterTurns ?? this.rotationQuarterTurns,
        flipHorizontal: flipHorizontal ?? this.flipHorizontal,
        flipVertical: flipVertical ?? this.flipVertical,
        cropRect: clearCrop ? null : (cropRect ?? this.cropRect),
      );

  bool get isDirty =>
      brightness != 0 ||
      contrast != 0 ||
      saturation != 0 ||
      rotationQuarterTurns != 0 ||
      flipHorizontal ||
      flipVertical ||
      cropRect != null;
}

@immutable
class CropRectNormalized {
  const CropRectNormalized(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => (right - left).clamp(0.0, 1.0);
  double get height => (bottom - top).clamp(0.0, 1.0);
}

class EditorController extends StateNotifier<EditorState> {
  EditorController(Uint8List source)
      : super(EditorState(sourceBytes: source));

  void setBrightness(int v) => state = state.copyWith(brightness: v);
  void setContrast(int v) => state = state.copyWith(contrast: v);
  void setSaturation(int v) => state = state.copyWith(saturation: v);
  void rotateClockwise() => state = state.copyWith(
      rotationQuarterTurns: (state.rotationQuarterTurns + 1) % 4);
  void flipHorizontal() =>
      state = state.copyWith(flipHorizontal: !state.flipHorizontal);
  void flipVertical() =>
      state = state.copyWith(flipVertical: !state.flipVertical);
  void setCrop(CropRectNormalized rect) => state = state.copyWith(cropRect: rect);
  void clearCrop() => state = state.copyWith(clearCrop: true);

  void reset() {
    state = EditorState(sourceBytes: state.sourceBytes);
  }

  /// 应用当前调整并导出 PNG。耗时操作,UI 层应用 compute()。
  Future<Uint8List> exportBytes() async {
    return applyAdjustments(state);
  }
}

/// 调整算法:在 isolate 内完成(顶层函数,compute() 可调用)。
/// 使用 image 包做像素级操作;饱和度用 HSV 空间调整。
Future<Uint8List> applyAdjustments(EditorState s) async {
  var src = img.decodeImage(s.sourceBytes);
  if (src == null) return s.sourceBytes;
  // 旋转 + 翻转
  if (s.rotationQuarterTurns != 0) {
    src = img.copyRotate(src, angle: s.rotationQuarterTurns * 90);
  }
  if (s.flipHorizontal && s.flipVertical) {
    src = img.flip(src, direction: img.FlipDirection.both);
  } else if (s.flipHorizontal) {
    src = img.flip(src, direction: img.FlipDirection.horizontal);
  } else if (s.flipVertical) {
    src = img.flip(src, direction: img.FlipDirection.vertical);
  }
  // 调色
  if (s.brightness != 0 || s.contrast != 0 || s.saturation != 0) {
    src = _adjustColors(src, s.brightness, s.contrast, s.saturation);
  }
  // 裁剪
  final crop = s.cropRect;
  if (crop != null && crop.width > 0 && crop.height > 0) {
    final x = (crop.left * src.width).round().clamp(0, src.width - 1);
    final y = (crop.top * src.height).round().clamp(0, src.height - 1);
    final w = (crop.width * src.width).round().clamp(1, src.width - x);
    final h = (crop.height * src.height).round().clamp(1, src.height - y);
    src = img.copyCrop(src, x: x, y: y, width: w, height: h);
  }
  return Uint8List.fromList(img.encodePng(src));
}

img.Image _adjustColors(img.Image src, int brightness, int contrast, int saturation) {
  // 预计算对比度因子:contrast ∈ [-100,100] → factor ∈ [0.5, 1.5]
  final cFactor = 1.0 + (contrast / 100.0);
  // 亮度直接加到 RGB
  final bDelta = brightness * 1.27; // -127..127

  for (final pixel in src) {
    // 亮度
    if (bDelta != 0) {
      pixel.r = (pixel.r + bDelta).clamp(0, 255).toInt();
      pixel.g = (pixel.g + bDelta).clamp(0, 255).toInt();
      pixel.b = (pixel.b + bDelta).clamp(0, 255).toInt();
    }
    // 对比度
    if (cFactor != 1.0) {
      pixel.r = ((pixel.r - 128) * cFactor + 128).clamp(0, 255).toInt();
      pixel.g = ((pixel.g - 128) * cFactor + 128).clamp(0, 255).toInt();
      pixel.b = ((pixel.b - 128) * cFactor + 128).clamp(0, 255).toInt();
    }
    // 饱和度:基于最大/最小通道差
    if (saturation != 0) {
      final gray = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).toInt();
      final sFactor = 1.0 + saturation / 100.0;
      pixel.r = ((gray + (pixel.r - gray) * sFactor).clamp(0, 255)).toInt();
      pixel.g = ((gray + (pixel.g - gray) * sFactor).clamp(0, 255)).toInt();
      pixel.b = ((gray + (pixel.b - gray) * sFactor).clamp(0, 255)).toInt();
    }
  }
  return src;
}

final editorControllerProvider =
    StateNotifierProvider.autoDispose.family<EditorController, EditorState, Uint8List>(
        (ref, bytes) => EditorController(bytes));