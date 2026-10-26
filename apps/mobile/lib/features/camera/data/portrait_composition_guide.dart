import 'dart:ui';

enum PortraitFraming { headshot, halfBody, fullBody, group }

/// 人像构图提示。文案使用建议语气，低置信度结果由 UI 过滤。
class PortraitCompositionHint {
  const PortraitCompositionHint({
    required this.code,
    required this.message,
    required this.confidence,
    required this.framing,
  });

  final String code;
  final String message;
  final double confidence;
  final PortraitFraming framing;
}

/// 基于人脸框和人体关键点的轻量构图评估。
///
/// 只做几何判断，不做身份识别，也不保存任何特征；输入坐标均为相对预览的
/// 0～1 归一化值，便于直接和实时画面共享坐标系。
class PortraitCompositionAnalyzer {
  const PortraitCompositionAnalyzer();

  static const double _edgeMargin = .045;

  PortraitCompositionHint? evaluate({
    required List<Rect> faces,
    required Map<String, Offset> landmarks,
  }) {
    final validFaces = faces
        .where(
          (face) =>
              face.width > .02 &&
              face.height > .02 &&
              face.left.isFinite &&
              face.top.isFinite,
        )
        .toList(growable: false);
    if (validFaces.isEmpty) return null;
    final framing = _framing(validFaces.length, landmarks);

    final edgeHint = _edgeRisk(landmarks, framing);
    if (edgeHint != null) return edgeHint;

    final sortedFaces = [...validFaces]
      ..sort((left, right) => left.left.compareTo(right.left));
    final top = sortedFaces.map((face) => face.top).reduce(_min);
    final averageHeight =
        sortedFaces.fold<double>(0, (sum, face) => sum + face.height) /
        sortedFaces.length;
    if (top < .05) {
      return PortraitCompositionHint(
        code: 'headroom_tight',
        message: '头顶留白偏少，可以稍微后退或抬高镜头',
        confidence: .9,
        framing: framing,
      );
    }
    if (top > .22 && averageHeight < .32) {
      return PortraitCompositionHint(
        code: 'headroom_loose',
        message: '头顶留白偏多，可以靠近一点让主体更突出',
        confidence: .75,
        framing: framing,
      );
    }

    if (framing == PortraitFraming.group) {
      final groupHint = _groupRisk(sortedFaces, framing);
      if (groupHint != null) return groupHint;
    }

    final union = sortedFaces.reduce(
      (left, right) => left.expandToInclude(right),
    );
    final centerX = union.center.dx;
    if (centerX < .34) {
      return PortraitCompositionHint(
        code: 'subject_left',
        message: '人物稍偏左，可以把镜头稍微向右移',
        confidence: .65,
        framing: framing,
      );
    }
    if (centerX > .66) {
      return PortraitCompositionHint(
        code: 'subject_right',
        message: '人物稍偏右，可以把镜头稍微向左移',
        confidence: .65,
        framing: framing,
      );
    }
    if (averageHeight < .14) {
      return PortraitCompositionHint(
        code: 'subject_far',
        message: '人物在画面里偏小，可以靠近一些',
        confidence: .6,
        framing: framing,
      );
    }
    return null;
  }

  PortraitFraming _framing(int faceCount, Map<String, Offset> landmarks) {
    if (faceCount > 1) return PortraitFraming.group;
    if (landmarks.containsKey('leftAnkle') &&
        landmarks.containsKey('rightAnkle')) {
      return PortraitFraming.fullBody;
    }
    if (landmarks.containsKey('leftHip') && landmarks.containsKey('rightHip')) {
      return PortraitFraming.halfBody;
    }
    if (landmarks.containsKey('leftShoulder') &&
        landmarks.containsKey('rightShoulder')) {
      return PortraitFraming.halfBody;
    }
    return PortraitFraming.headshot;
  }

  PortraitCompositionHint? _edgeRisk(
    Map<String, Offset> landmarks,
    PortraitFraming framing,
  ) {
    const checks = <(List<String>, String, String)>[
      (['leftEye', 'rightEye'], 'eye_edge', '眼睛贴近画面边缘，稍微调整构图会更自然'),
      (['leftWrist', 'rightWrist'], 'wrist_edge', '手腕贴边，动作容易拍不完整'),
      (['leftKnee', 'rightKnee'], 'knee_edge', '膝盖卡在边缘，建议后退半步'),
      (['leftAnkle', 'rightAnkle'], 'ankle_edge', '脚踝贴边，全身照建议再后退一点'),
    ];
    for (final (keys, code, message) in checks) {
      for (final key in keys) {
        final point = landmarks[key];
        if (point == null) continue;
        if (point.dx < _edgeMargin ||
            point.dx > 1 - _edgeMargin ||
            point.dy < _edgeMargin ||
            point.dy > 1 - _edgeMargin) {
          return PortraitCompositionHint(
            code: code,
            message: message,
            confidence: .85,
            framing: framing,
          );
        }
      }
    }
    return null;
  }

  PortraitCompositionHint? _groupRisk(
    List<Rect> faces,
    PortraitFraming framing,
  ) {
    for (var index = 1; index < faces.length; index++) {
      if (faces[index - 1].overlaps(faces[index])) {
        return PortraitCompositionHint(
          code: 'group_overlap',
          message: '两人站得有些近，注意不要互相遮挡',
          confidence: .8,
          framing: framing,
        );
      }
    }
    final averageWidth =
        faces.fold<double>(0, (sum, face) => sum + face.width) / faces.length;
    for (var index = 1; index < faces.length; index++) {
      final gap = faces[index].left - faces[index - 1].right;
      if (gap > averageWidth * 1.6) {
        return PortraitCompositionHint(
          code: 'group_spread',
          message: '合影站位有些分散，可以靠近一点更紧凑',
          confidence: .7,
          framing: framing,
        );
      }
    }
    return null;
  }

  static double _min(double left, double right) => left < right ? left : right;
}
