import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

ImageFormatGroup get preferredAnalysisFormat =>
    Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21;

class LiveCameraAnalysis {
  const LiveCameraAnalysis({
    required this.landmarks,
    required this.suggestion,
    required this.scene,
    required this.sceneConfidence,
  });

  /// 关键点坐标已归一化，并按前置摄像头完成镜像，可直接用于预览叠加。
  final Map<String, Offset> landmarks;
  final String suggestion;
  final String scene;
  final double sceneConfidence;
}

class LiveCameraAnalyzer {
  LiveCameraAnalyzer()
      : _poseDetector = PoseDetector(
          options: PoseDetectorOptions(
            model: PoseDetectionModel.base,
            mode: PoseDetectionMode.stream,
          ),
        ),
        _labeler = ImageLabeler(
          options: ImageLabelerOptions(confidenceThreshold: .55),
        );

  final PoseDetector _poseDetector;
  final ImageLabeler _labeler;
  bool _processing = false;
  bool _closed = false;
  int _frameNumber = 0;
  String _scene = '识别场景中';
  double _sceneConfidence = 0;
  Map<String, Offset> _smoothed = const {};

  Future<LiveCameraAnalysis?> process(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_processing || _closed || image.planes.length != 1) return null;
    final input = _toInputImage(image, camera);
    if (input == null) return null;
    _processing = true;
    try {
      final poses = await _poseDetector.processImage(input);
      // 图像标签比姿态检测更重，每 5 次姿态推理运行一次。
      if (_frameNumber++ % 5 == 0) {
        final labels = await _labeler.processImage(input);
        final scene = _classifyScene(labels);
        _scene = scene.$1;
        _sceneConfidence = scene.$2;
      }
      final landmarks = poses.isEmpty
          ? <String, Offset>{}
          : _normalize(poses.first, image, camera);
      _smoothed = _smooth(_smoothed, landmarks);
      return LiveCameraAnalysis(
        landmarks: _smoothed,
        suggestion: _poseSuggestion(_smoothed),
        scene: _scene,
        sceneConfidence: _sceneConfidence,
      );
    } catch (_) {
      // 部分设备不支持流格式时不影响拍照主流程。
      return null;
    } finally {
      _processing = false;
    }
  }

  InputImage? _toInputImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null) return null;
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Map<String, Offset> _normalize(
    Pose pose,
    CameraImage image,
    CameraDescription camera,
  ) {
    final rotated =
        camera.sensorOrientation == 90 || camera.sensorOrientation == 270;
    final width = rotated ? image.height.toDouble() : image.width.toDouble();
    final height = rotated ? image.width.toDouble() : image.height.toDouble();
    final result = <String, Offset>{};
    for (final entry in pose.landmarks.entries) {
      final point = entry.value;
      if (point.likelihood < .55) continue;
      var x = (point.x / width).clamp(0.0, 1.0);
      final y = (point.y / height).clamp(0.0, 1.0);
      if (camera.lensDirection == CameraLensDirection.front) x = 1 - x;
      result[entry.key.name] = Offset(x, y);
    }
    return result;
  }

  Map<String, Offset> _smooth(
    Map<String, Offset> previous,
    Map<String, Offset> current,
  ) {
    if (current.isEmpty) return const {};
    return current.map((key, point) {
      final old = previous[key];
      return MapEntry(
        key,
        old == null ? point : Offset.lerp(old, point, .35)!,
      );
    });
  }

  String _poseSuggestion(Map<String, Offset> points) {
    if (points.isEmpty) return '未识别到完整人物，请面向镜头并适当后退';
    final nose = points['nose'];
    final leftShoulder = points['leftShoulder'];
    final rightShoulder = points['rightShoulder'];
    final leftHip = points['leftHip'];
    final rightHip = points['rightHip'];
    final leftAnkle = points['leftAnkle'];
    final rightAnkle = points['rightAnkle'];
    if (nose == null || leftShoulder == null || rightShoulder == null) {
      return '请面向镜头，让头部和双肩清晰入镜';
    }
    if (leftHip == null || rightHip == null) {
      return '稍微后退一些，让上半身完整入镜';
    }
    if (leftAnkle == null || rightAnkle == null) {
      return '想拍全身照时请再后退一步，露出双脚';
    }
    final shoulderAngle = math.atan2(
          rightShoulder.dy - leftShoulder.dy,
          rightShoulder.dx - leftShoulder.dx,
        ) *
        180 /
        math.pi;
    if (shoulderAngle.abs() > 10) return '肩线有些倾斜，轻轻调整身体会更自然';
    final centerX = (leftHip.dx + rightHip.dx) / 2;
    if (centerX < .32) return '人物稍向右移动，画面会更平衡';
    if (centerX > .68) return '人物稍向左移动，给视线方向留出空间';
    return '姿态很好，保持当前站位';
  }

  (String, double) _classifyScene(List<ImageLabel> labels) {
    if (labels.isEmpty) return ('通用场景', 0);
    const groups = <String, List<String>>{
      '人像': ['person', 'people', 'face', 'human', 'fashion'],
      '美食': ['food', 'dish', 'cuisine', 'meal', 'dessert', 'fruit'],
      '宠物': ['dog', 'cat', 'pet', 'animal'],
      '风景': ['landscape', 'sky', 'mountain', 'beach', 'nature', 'plant'],
      '建筑': ['building', 'architecture', 'house', 'city'],
      '夜景': ['night', 'darkness', 'neon'],
      '室内': ['room', 'furniture', 'interior'],
    };
    for (final label in labels) {
      final text = label.label.toLowerCase();
      for (final group in groups.entries) {
        if (group.value.any(text.contains)) {
          return (group.key, label.confidence);
        }
      }
    }
    return ('通用场景', labels.first.confidence);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait([_poseDetector.close(), _labeler.close()]);
  }
}
