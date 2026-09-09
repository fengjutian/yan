import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceAnalysis {
  const FaceAnalysis({required this.faceCount, required this.suggestion});
  final int faceCount;
  final String suggestion;
}

Future<FaceAnalysis> analyzeFaces(String path, int width, int height) async {
  final detector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
  try {
    final faces = await detector.processImage(InputImage.fromFilePath(path));
    if (faces.isEmpty) return const FaceAnalysis(faceCount: 0, suggestion: '未检测到人物，可尝试靠近镜头或面向光源');
    final face = faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
    final center = face.boundingBox.center;
    final x = center.dx / width;
    final y = center.dy / height;
    var suggestion = '人物位置很好，保持当前构图';
    if (x < .25) suggestion = '人物稍向右移动，画面会更平衡';
    if (x > .75) suggestion = '人物稍向左移动，保留视线方向的空间';
    if (y < .22) suggestion = '镜头稍微上移，避免头顶空间过多';
    if (y > .68) suggestion = '镜头稍微降低，让人物重心更稳定';
    return FaceAnalysis(faceCount: faces.length, suggestion: suggestion);
  } finally {
    await detector.close();
  }
}
