import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

ImageFormatGroup get preferredAnalysisFormat => ImageFormatGroup.jpeg;

class LiveCameraAnalysis {
  const LiveCameraAnalysis({
    this.landmarks = const {},
    this.suggestion = '将人物放在构图线交叉点附近',
    this.scene = '通用场景',
    this.sceneConfidence = 0,
  });

  final Map<String, Offset> landmarks;
  final String suggestion;
  final String scene;
  final double sceneConfidence;
}

class LiveCameraAnalyzer {
  Future<LiveCameraAnalysis?> process(
    CameraImage image,
    CameraDescription camera,
  ) async =>
      null;

  Future<void> close() async {}
}
