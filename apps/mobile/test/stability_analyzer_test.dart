import 'package:ai_image_studio/features/camera/data/stability_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 1, 1, 12);

  test('静止设备保持稳定且获得高分', () {
    final analyzer = StabilityAnalyzer();
    var snapshot = analyzer.snapshot;
    for (var index = 0; index < 10; index++) {
      snapshot = analyzer.ingest(
        0,
        0,
        9.8,
        at: start.add(Duration(milliseconds: 120 * index)),
      );
    }

    expect(snapshot.hasSamples, isTrue);
    expect(snapshot.score, greaterThan(95));
    expect(snapshot.stable, isTrue);
    expect(
      snapshot.stableFor,
      greaterThanOrEqualTo(StabilityRequirement.standard.minStableDuration),
    );
    expect(snapshot.guidance, '可以拍摄');
    expect(snapshot.captureScore, closeTo(snapshot.score, .001));
  });

  test('明显移动时不会进入稳定状态', () {
    final analyzer = StabilityAnalyzer();
    var snapshot = analyzer.snapshot;
    for (var index = 0; index < 12; index++) {
      // 交替偏移 1.8g，模拟走路拍摄时的手抖。
      snapshot = analyzer.ingest(
        index.isEven ? 0 : 1.8,
        0,
        9.8,
        at: start.add(Duration(milliseconds: 120 * index)),
      );
      expect(snapshot.stable, isFalse);
    }

    expect(snapshot.motion, greaterThan(.3));
    expect(snapshot.score, lessThan(60));
    expect(snapshot.stableFor, Duration.zero);
    expect(snapshot.guidance, '请保持稳定');
  });

  test('轻微运动在普通模式可拍摄，在严格模式被拒绝', () {
    final analyzer = StabilityAnalyzer();
    var snapshot = analyzer.snapshot;
    var x = 0.0;
    for (var index = 0; index < 9; index++) {
      // 每次采样偏移 0.135g：平滑后约 0.06g，处于两档阈值之间。
      x += .135;
      snapshot = analyzer.ingest(
        x,
        0,
        9.8,
        at: start.add(Duration(milliseconds: 120 * index)),
      );
    }

    expect(snapshot.stable, isTrue);
    analyzer.setRequirement(StabilityRequirement.strict);
    snapshot = analyzer.snapshot;
    expect(snapshot.stable, isFalse);
    expect(snapshot.requirement, StabilityRequirement.strict);
  });

  test('严格模式需要更长的稳定时间', () {
    final analyzer = StabilityAnalyzer(
      requirement: StabilityRequirement.strict,
    );
    var snapshot = analyzer.snapshot;
    for (var index = 0; index < 7; index++) {
      snapshot = analyzer.ingest(
        0,
        0,
        9.8,
        at: start.add(Duration(milliseconds: 120 * index)),
      );
    }
    // 720ms：满足普通模式，但不足严格模式的 900ms。
    expect(
      snapshot.stableFor,
      lessThan(StabilityRequirement.strict.minStableDuration),
    );
    expect(snapshot.stable, isFalse);

    for (var index = 7; index < 10; index++) {
      snapshot = analyzer.ingest(
        0,
        0,
        9.8,
        at: start.add(Duration(milliseconds: 120 * index)),
      );
    }
    expect(snapshot.stable, isTrue);
  });

  test('reset 后不再提供拍摄稳定分', () {
    final analyzer = StabilityAnalyzer();
    analyzer.ingest(0, 0, 9.8, at: start);
    analyzer.ingest(0, 0, 9.8, at: start.add(const Duration(seconds: 1)));
    expect(analyzer.snapshot.hasSamples, isTrue);

    analyzer.reset();

    expect(analyzer.snapshot.hasSamples, isFalse);
    expect(analyzer.snapshot.captureScore, isNull);
    expect(analyzer.snapshot.guidance, isNull);
    expect(analyzer.snapshot.isStale(), isTrue);
  });

  test('过期快照不应继续展示', () {
    final analyzer = StabilityAnalyzer();
    final snapshot = analyzer.ingest(0, 0, 9.8, at: start);
    expect(
      snapshot.isStale(start.add(const Duration(milliseconds: 600))),
      isFalse,
    );
    expect(snapshot.isStale(start.add(const Duration(seconds: 2))), isTrue);
  });
}
