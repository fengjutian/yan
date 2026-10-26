import 'dart:io';
import 'dart:math' as math;

import 'package:ai_image_studio/features/camera/data/photo_quality.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 用 ML Kit 分析单张照片的人像质量。
///
/// - 开启轮廓、关键点、睁眼和笑容分类；
/// - 人脸清晰度在 isolate 中计算，避免阻塞 UI；
/// - 任一步骤失败时返回 null，调用方保留通用评分继续选片。
Future<PortraitQualityMetrics?> analyzePortraitQuality(Uint8List bytes) async {
  FaceDetector? detector;
  File? file;
  try {
    final normalized = await compute(_normalizeForDetection, bytes);
    final directory = await getTemporaryDirectory();
    file = File(
      '${directory.path}/yan-portrait-'
      '${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(normalized, flush: true);
    detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: true,
        enableLandmarks: true,
        enableContours: true,
        minFaceSize: .08,
      ),
    );
    final faces = await detector.processImage(
      InputImage.fromFilePath(file.path),
    );
    if (faces.isEmpty) {
      return const PortraitQualityMetrics(
        faceCount: 0,
        faceSharpness: 0,
        eyesOpenScore: 0,
        smileScore: 0,
        occlusionRisk: 0,
      );
    }
    final eyeScores = <double>[];
    var smileScore = 0.0;
    var occlusionTotal = 0.0;
    final rects = <double>[];
    for (final face in faces) {
      rects.addAll([
        face.boundingBox.left,
        face.boundingBox.top,
        face.boundingBox.right,
        face.boundingBox.bottom,
      ]);
      final eyes = [
        face.leftEyeOpenProbability,
        face.rightEyeOpenProbability,
      ].whereType<double>().toList(growable: false);
      // 单只眼闭合也会明显拉低该人脸的睁眼分数。
      eyeScores.add(eyes.isEmpty ? 50.0 : eyes.reduce(math.min) * 100);
      smileScore = math.max(smileScore, (face.smilingProbability ?? 0) * 100);
      occlusionTotal += _occlusionRisk(face);
    }
    final faceSharpness = await compute(_faceSharpness, (normalized, rects));
    return PortraitQualityMetrics(
      faceCount: faces.length,
      faceSharpness: faceSharpness,
      eyesOpenScore: eyeScores.reduce(math.min).clamp(0, 100).toDouble(),
      smileScore: smileScore.clamp(0, 100).toDouble(),
      occlusionRisk: (occlusionTotal / faces.length).clamp(0, 100).toDouble(),
    );
  } catch (_) {
    // 部分设备缺少人脸分类模型；失败时只关闭人像能力。
    return null;
  } finally {
    await detector?.close();
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // 临时文件清理失败不影响拍摄结果。
      }
    }
  }
}

double _occlusionRisk(Face face) {
  var risk = 0.0;
  if (face.leftEyeOpenProbability == null &&
      face.rightEyeOpenProbability == null) {
    risk += 15;
  }
  final angleY = face.headEulerAngleY;
  if (angleY != null && angleY.abs() > 25) risk += 25;
  const required = [
    FaceLandmarkType.leftEye,
    FaceLandmarkType.rightEye,
    FaceLandmarkType.noseBase,
    FaceLandmarkType.leftMouth,
    FaceLandmarkType.rightMouth,
    FaceLandmarkType.bottomMouth,
  ];
  final missing = required.where((type) => face.landmarks[type] == null).length;
  risk += missing * 7;
  return risk.clamp(0, 100).toDouble();
}

/// 将照片缩到人脸检测友好的尺寸，同时烘焙方向，减少 ML Kit 的耗时和内存。
Uint8List _normalizeForDetection(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = img.bakeOrientation(decoded);
  const maxEdge = 1600;
  if (image.width > maxEdge || image.height > maxEdge) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxEdge)
        : img.copyResize(image, height: maxEdge);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// 在缩小后的图像上估算人脸区域的边缘清晰度。
double _faceSharpness((Uint8List, List<double>) input) {
  final (bytes, rects) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null || rects.length < 4) return 0;
  final width = math.min(240, decoded.width);
  final image = img.copyResize(decoded, width: width);
  final scaleX = image.width / decoded.width;
  final scaleY = image.height / decoded.height;
  double gray(int x, int y) {
    final pixel = image.getPixel(x, y);
    return .299 * pixel.r + .587 * pixel.g + .114 * pixel.b;
  }

  var total = 0.0;
  var samples = 0;
  for (var index = 0; index + 3 < rects.length; index += 4) {
    final left = (rects[index] * scaleX)
        .round()
        .clamp(1, image.width - 2)
        .toInt();
    final top = (rects[index + 1] * scaleY)
        .round()
        .clamp(1, image.height - 2)
        .toInt();
    final right = (rects[index + 2] * scaleX)
        .round()
        .clamp(left + 1, image.width - 1)
        .toInt();
    final bottom = (rects[index + 3] * scaleY)
        .round()
        .clamp(top + 1, image.height - 1)
        .toInt();
    final step = math.max(1, math.min(right - left, bottom - top) ~/ 24);
    for (var y = top; y < bottom; y += step) {
      for (var x = left; x < right; x += step) {
        final center = gray(x, y);
        total += (center - gray(x + 1, y)).abs();
        total += (center - gray(x, y + 1)).abs();
        samples++;
      }
    }
  }
  if (samples == 0) return 0;
  return (total / samples * 2.6).clamp(0, 100).toDouble();
}
