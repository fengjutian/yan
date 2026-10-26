import 'package:ai_image_studio/features/camera/data/photo_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const portrait = PortraitQualityMetrics(
    faceCount: 2,
    faceSharpness: 80,
    eyesOpenScore: 95,
    smileScore: 70,
    occlusionRisk: 10,
  );

  test('手抖惩罚只影响有稳定度数据的照片', () {
    expect(PhotoQualityEvaluator.applyStability(80, null), 80);
    expect(PhotoQualityEvaluator.applyStability(80, 100), closeTo(80, .001));
    expect(PhotoQualityEvaluator.applyStability(80, 50), closeTo(72, .001));
    expect(PhotoQualityEvaluator.applyStability(10, 0), closeTo(0, .001));
  });

  test('相同画质下更稳定的照片得分更高', () {
    final shaky = PhotoQualityEvaluator.applyStability(80, 40);
    final steady = PhotoQualityEvaluator.applyStability(80, 95);
    expect(steady, greaterThan(shaky));
  });

  test('人像评分按 55/20/15/10 合并', () {
    final merged = PhotoQualityEvaluator.mergePortrait(80, portrait);
    final expected =
        80 * .55 + 80 * .20 + 95 * .15 + portrait.expressionScore * .10;
    expect(merged, closeTo(expected, .001));
  });

  test('闭眼人像不会比睁眼人像得分高', () {
    const closed = PortraitQualityMetrics(
      faceCount: 2,
      faceSharpness: 80,
      eyesOpenScore: 0,
      smileScore: 70,
      occlusionRisk: 10,
    );
    final openScore = PhotoQualityEvaluator.mergePortrait(80, portrait);
    final closedScore = PhotoQualityEvaluator.mergePortrait(80, closed);
    expect(openScore, greaterThan(closedScore));
  });

  test('没有人物时不扣分', () {
    const empty = PortraitQualityMetrics(
      faceCount: 0,
      faceSharpness: 0,
      eyesOpenScore: 0,
      smileScore: 0,
      occlusionRisk: 0,
    );
    expect(PhotoQualityEvaluator.mergePortrait(72, empty), 72);
    expect(PhotoQualityEvaluator.mergePortrait(72, null), 72);
  });

  test('推荐原因解释人像与稳定性', () {
    final reasons = PhotoQualityEvaluator.describe(
      sharpness: 80,
      exposure: 82,
      contrast: 65,
      clippingPenalty: 2,
      stability: 90,
      portrait: portrait,
    );
    expect(reasons, containsAll(['人物清晰', '全员睁眼', '表情自然']));

    final label = PhotoQualityEvaluator.label(
      score: 90,
      sharpness: 80,
      exposure: 82,
      clippingPenalty: 2,
      stability: 90,
      portrait: portrait,
    );
    expect(label, '优质');
  });

  test('闭眼和手抖会体现在质量标签上', () {
    const closed = PortraitQualityMetrics(
      faceCount: 1,
      faceSharpness: 80,
      eyesOpenScore: 10,
      smileScore: 40,
      occlusionRisk: 10,
    );
    expect(
      PhotoQualityEvaluator.label(
        score: 70,
        sharpness: 80,
        exposure: 80,
        clippingPenalty: 0,
        portrait: closed,
      ),
      '有人闭眼',
    );
    expect(
      PhotoQualityEvaluator.label(
        score: 70,
        sharpness: 80,
        exposure: 80,
        clippingPenalty: 0,
        stability: 30,
      ),
      '手抖偏多',
    );
  });
}
