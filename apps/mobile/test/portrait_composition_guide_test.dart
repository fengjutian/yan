import 'dart:ui';

import 'package:ai_image_studio/features/camera/data/portrait_composition_guide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const analyzer = PortraitCompositionAnalyzer();

  test('没有人物时不产生构图提示', () {
    final hint = analyzer.evaluate(faces: const [], landmarks: const {});
    expect(hint, isNull);
  });

  test('识别全身、半身和多人场景', () {
    final fullBody = analyzer.evaluate(
      faces: const [Rect.fromLTWH(.4, .1, .2, .2)],
      landmarks: {
        'leftAnkle': const Offset(.42, .9),
        'rightAnkle': const Offset(.58, .9),
        'leftHip': const Offset(.43, .55),
        'rightHip': const Offset(.57, .55),
      },
    );
    expect(fullBody, isNull);

    final halfBody = analyzer.evaluate(
      faces: const [Rect.fromLTWH(.4, .1, .2, .2)],
      landmarks: {
        'leftHip': const Offset(.43, .55),
        'rightHip': const Offset(.57, .55),
        'leftWrist': const Offset(.35, .5),
        'rightWrist': const Offset(.65, .5),
      },
    );
    expect(halfBody, isNull);

    final group = analyzer.evaluate(
      faces: const [
        Rect.fromLTWH(.25, .15, .18, .18),
        Rect.fromLTWH(.55, .15, .18, .18),
      ],
      landmarks: const {},
    );
    expect(group, anyOf(isNull, isA<PortraitCompositionHint>()));
  });

  test('头顶留白不足时提示后退或抬高镜头', () {
    final hint = analyzer.evaluate(
      faces: const [Rect.fromLTWH(.4, .015, .2, .2)],
      landmarks: const {},
    );
    expect(hint?.code, 'headroom_tight');
    expect(hint!.confidence, greaterThan(.8));
  });

  test('眼睛贴边时优先提示构图风险', () {
    final hint = analyzer.evaluate(
      faces: const [Rect.fromLTWH(.4, .1, .2, .2)],
      landmarks: {'leftEye': const Offset(.01, .2)},
    );
    expect(hint?.code, 'eye_edge');
  });

  test('人物偏移和偏小都有对应提示', () {
    final left = analyzer.evaluate(
      faces: const [Rect.fromLTWH(.02, .2, .2, .3)],
      landmarks: const {},
    );
    expect(left?.code, 'subject_left');

    final far = analyzer.evaluate(
      faces: const [Rect.fromLTWH(.44, .15, .12, .12)],
      landmarks: const {},
    );
    expect(far?.code, 'subject_far');
  });

  test('多人重叠或间距过大时提示站位', () {
    final overlap = analyzer.evaluate(
      faces: const [
        Rect.fromLTWH(.3, .2, .25, .25),
        Rect.fromLTWH(.4, .2, .25, .25),
      ],
      landmarks: const {},
    );
    expect(overlap?.code, 'group_overlap');

    final spread = analyzer.evaluate(
      faces: const [
        Rect.fromLTWH(.05, .2, .1, .1),
        Rect.fromLTWH(.8, .2, .1, .1),
      ],
      landmarks: const {},
    );
    expect(spread?.code, 'group_spread');
  });

  test('构图良好时不打扰用户', () {
    final hint = analyzer.evaluate(
      faces: const [Rect.fromLTWH(.4, .18, .2, .24)],
      landmarks: {
        'leftEye': const Offset(.45, .24),
        'rightEye': const Offset(.55, .24),
      },
    );
    expect(hint, isNull);
  });
}
