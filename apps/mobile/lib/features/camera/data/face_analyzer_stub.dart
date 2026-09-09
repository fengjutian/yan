class FaceAnalysis {
  const FaceAnalysis({this.faceCount = 0, this.suggestion = '将人物放在构图线交叉点附近'});
  final int faceCount;
  final String suggestion;
}

Future<FaceAnalysis> analyzeFaces(String path, int width, int height) async =>
    const FaceAnalysis();
