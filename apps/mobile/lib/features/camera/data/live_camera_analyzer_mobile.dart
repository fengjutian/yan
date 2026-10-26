import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
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
    required this.smileDetected,
    required this.gestureDetected,
    this.faces = const [],
    this.barcodeValue,
    this.barcodeType,
  });

  /// 关键点坐标已归一化，并按前置摄像头完成镜像，可直接用于预览叠加。
  final Map<String, Offset> landmarks;
  final String suggestion;
  final String scene;
  final double sceneConfidence;
  final bool smileDetected;
  final bool gestureDetected;

  /// 人脸框已归一化并镜像，可直接用于构图判断。
  final List<Rect> faces;
  final String? barcodeValue;
  final String? barcodeType;
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
      ),
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableClassification: true,
          minFaceSize: .15,
        ),
      );

  final PoseDetector _poseDetector;
  final ImageLabeler _labeler;
  final FaceDetector _faceDetector;
  BarcodeScanner? _barcodeScanner;
  bool _processing = false;
  bool _closed = false;
  bool _poseAvailable = true;
  bool _labelAvailable = true;
  bool _faceAvailable = true;
  bool _barcodeAvailable = true;
  bool _sceneDetectionActive = true;
  int _frameNumber = 0;
  String _scene = '识别场景中';
  double _sceneConfidence = 0;
  Map<String, Offset> _smoothed = const {};
  List<Rect> _faces = const [];
  bool _smileDetected = false;
  String? _barcodeValue;
  String? _barcodeType;

  Future<LiveCameraAnalysis?> process(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation, {
    bool scanBarcodes = false,
    bool detectPose = true,
    bool detectFace = true,
    bool detectScene = true,
  }) async {
    if (_processing || _closed || image.planes.length != 1) return null;
    final rotation = _inputRotation(camera, deviceOrientation);
    if (rotation == null) return null;
    final input = _toInputImage(image, rotation);
    if (input == null) return null;
    _processing = true;
    try {
      // 每个分析器独立降级：某一项失败只关闭对应能力，姿态、场景、
      // 人像和扫码之间互不阻塞，也不会让整次分析返回空。
      final poses = <Pose>[];
      if (detectPose && _poseAvailable) {
        try {
          poses.addAll(await _poseDetector.processImage(input));
        } catch (_) {
          _poseAvailable = false;
        }
      }
      final frameNumber = _frameNumber++;
      // 图像标签比姿态检测更重：引导关闭时完全不运行，开启后约 2～4 秒一次。
      // 从关闭切回开启时强制补一次，避免场景 chip 长时间显示旧结果。
      final labelDue =
          detectScene &&
          _labelAvailable &&
          (!_sceneDetectionActive || frameNumber % 10 == 0);
      _sceneDetectionActive = detectScene;
      if (labelDue) {
        try {
          final labels = await _labeler.processImage(input);
          final scene = _classifyScene(labels);
          _scene = scene.$1;
          _sceneConfidence = scene.$2;
        } catch (_) {
          _labelAvailable = false;
        }
      }
      if (detectFace && _faceAvailable && frameNumber % 3 == 0) {
        try {
          final faces = await _faceDetector.processImage(input);
          _smileDetected = faces.any(
            (face) => (face.smilingProbability ?? 0) >= .75,
          );
          _faces = _normalizeFaces(faces, image, camera, rotation);
        } catch (_) {
          _faceAvailable = false;
          _faces = const [];
          _smileDetected = false;
        }
      }
      if (scanBarcodes && frameNumber % 2 == 0) {
        if (_barcodeAvailable) {
          try {
            // 扫码是低频能力，首次进入扫码模式时才创建检测器，避免
            // 普通拍摄会话也承担模型加载和内存占用。
            final barcodeScanner = _barcodeScanner ??= BarcodeScanner();
            final barcodes = await barcodeScanner.processImage(input);
            if (barcodes.isEmpty) {
              _barcodeValue = null;
              _barcodeType = null;
            } else {
              final barcode = barcodes.first;
              _barcodeValue = barcode.rawValue ?? barcode.displayValue;
              _barcodeType = barcode.type.name;
            }
          } catch (_) {
            _barcodeAvailable = false;
            _barcodeValue = null;
            _barcodeType = null;
          }
        }
      } else if (!scanBarcodes) {
        _barcodeValue = null;
        _barcodeType = null;
      }
      final landmarks = detectPose && poses.isNotEmpty
          ? _normalize(poses.first, image, camera, rotation)
          : <String, Offset>{};
      if (detectPose) {
        _smoothed = _poseAvailable ? _smooth(_smoothed, landmarks) : const {};
      }
      return LiveCameraAnalysis(
        landmarks: detectPose ? _smoothed : const {},
        suggestion: !detectPose
            ? '实时姿态指导已关闭'
            : _poseAvailable
            ? _poseSuggestion(_smoothed)
            : '实时姿态分析暂不可用，仍可正常拍摄',
        scene: _scene,
        sceneConfidence: _sceneConfidence,
        smileDetected: detectFace && _smileDetected,
        gestureDetected: detectPose && _hasRaisedHand(_smoothed),
        faces: detectFace ? _faces : const [],
        barcodeValue: _barcodeValue,
        barcodeType: _barcodeType,
      );
    } catch (_) {
      // 部分设备不支持流格式时不影响拍照主流程。
      return null;
    } finally {
      _processing = false;
    }
  }

  bool _hasRaisedHand(Map<String, Offset> points) {
    final leftWrist = points['leftWrist'];
    final rightWrist = points['rightWrist'];
    final leftShoulder = points['leftShoulder'];
    final rightShoulder = points['rightShoulder'];
    return (leftWrist != null &&
            leftShoulder != null &&
            leftWrist.dy < leftShoulder.dy - .06) ||
        (rightWrist != null &&
            rightShoulder != null &&
            rightWrist.dy < rightShoulder.dy - .06);
  }

  InputImageRotation? _inputRotation(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    }
    const orientationDegrees = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final deviceDegrees = orientationDegrees[deviceOrientation];
    if (deviceDegrees == null) return null;
    final degrees = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + deviceDegrees) % 360
        : (camera.sensorOrientation - deviceDegrees + 360) % 360;
    return InputImageRotationValue.fromRawValue(degrees);
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
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
    InputImageRotation rotation,
  ) {
    final rotated =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
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
      return MapEntry(key, old == null ? point : Offset.lerp(old, point, .35)!);
    });
  }

  List<Rect> _normalizeFaces(
    List<Face> faces,
    CameraImage image,
    CameraDescription camera,
    InputImageRotation rotation,
  ) {
    final rotated =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final width = rotated ? image.height.toDouble() : image.width.toDouble();
    final height = rotated ? image.width.toDouble() : image.height.toDouble();
    final result = <Rect>[];
    for (final face in faces) {
      final box = face.boundingBox;
      var left = (box.left / width).clamp(0.0, 1.0);
      var right = (box.right / width).clamp(0.0, 1.0);
      final top = (box.top / height).clamp(0.0, 1.0);
      final bottom = (box.bottom / height).clamp(0.0, 1.0);
      if (camera.lensDirection == CameraLensDirection.front) {
        final mirroredLeft = 1 - right;
        right = 1 - left;
        left = mirroredLeft;
      }
      if (right > left && bottom > top) {
        result.add(Rect.fromLTRB(left, top, right, bottom));
      }
    }
    return result;
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
    final shoulderAngle =
        math.atan2(
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
    final barcodeScanner = _barcodeScanner;
    _barcodeScanner = null;
    await Future.wait([
      _poseDetector.close(),
      _labeler.close(),
      _faceDetector.close(),
      if (barcodeScanner != null) barcodeScanner.close(),
    ]);
  }
}
