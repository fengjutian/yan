import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

ImageFormatGroup get preferredAnalysisFormat => ImageFormatGroup.jpeg;

class LiveCameraAnalysis {
  const LiveCameraAnalysis({
    this.landmarks = const {},
    this.suggestion = '将人物放在构图线交叉点附近',
    this.scene = '通用场景',
    this.sceneConfidence = 0,
    this.smileDetected = false,
    this.gestureDetected = false,
    this.barcodeValue,
    this.barcodeType,
  });

  final Map<String, Offset> landmarks;
  final String suggestion;
  final String scene;
  final double sceneConfidence;
  final bool smileDetected;
  final bool gestureDetected;
  final String? barcodeValue;
  final String? barcodeType;
}

class LiveCameraAnalyzer {
  Future<LiveCameraAnalysis?> process(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation, {
    bool scanBarcodes = false,
  }) async => null;

  Future<void> close() async {}
}
