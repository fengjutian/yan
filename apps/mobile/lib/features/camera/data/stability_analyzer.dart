import 'dart:math' as math;

/// 拍摄稳定度要求。夜景、HDR 等长曝光场景使用更严格的阈值，
/// 避免快门在轻微晃动时触发而拍糊。
enum StabilityRequirement {
  standard(
    maxMotion: .12,
    minStableDuration: Duration(milliseconds: 450),
    label: '手持',
  ),
  strict(
    maxMotion: .06,
    minStableDuration: Duration(milliseconds: 900),
    label: '严格',
  );

  const StabilityRequirement({
    required this.maxMotion,
    required this.minStableDuration,
    required this.label,
  });

  /// 相邻采样之间的加速度变化量（g），低于该值视为稳定。
  final double maxMotion;
  final Duration minStableDuration;
  final String label;
}

/// 某一时刻的稳定度快照。所有字段均为纯数据，方便在 UI 和分析层之间传递。
class StabilitySnapshot {
  const StabilitySnapshot({
    required this.motion,
    required this.score,
    required this.stableFor,
    required this.stable,
    required this.requirement,
    required this.updatedAt,
    required this.hasSamples,
  });

  const StabilitySnapshot.initial()
    : motion = 0,
      score = 0,
      stableFor = Duration.zero,
      stable = false,
      requirement = StabilityRequirement.standard,
      updatedAt = null,
      hasSamples = false;

  /// 平滑后的手抖强度，0 表示完全静止。
  final double motion;

  /// 0～100 的稳定度分数，可直接写入照片质量指标。
  final double score;

  /// 当前已连续稳定的时长。
  final Duration stableFor;

  /// 是否达到当前的稳定阈值和最短稳定时长。
  final bool stable;

  final StabilityRequirement requirement;

  /// 最后一次采样的时间；为 null 表示传感器尚未上报。
  final DateTime? updatedAt;

  final bool hasSamples;

  /// 超过 1.2 秒没有新采样时不再展示，避免 UI 显示过期结果。
  bool isStale([DateTime? now]) {
    final at = updatedAt;
    if (at == null) return true;
    return (now ?? DateTime.now()).difference(at) >
        const Duration(milliseconds: 1200);
  }

  /// 非阻塞提示文案；传感器不可用时返回 null，由 UI 隐藏提示。
  String? get guidance {
    if (!hasSamples) return null;
    if (stable) return '可以拍摄';
    if (motion <= requirement.maxMotion) return '即将稳定';
    return '请保持稳定';
  }

  /// 拍摄时写入质量指标的值；没有采样时返回 null，评分自动退化为不含稳定分。
  double? get captureScore => hasSamples ? score : null;

  StabilitySnapshot copyWith({
    double? motion,
    double? score,
    Duration? stableFor,
    bool? stable,
    StabilityRequirement? requirement,
    DateTime? updatedAt,
    bool? hasSamples,
  }) => StabilitySnapshot(
    motion: motion ?? this.motion,
    score: score ?? this.score,
    stableFor: stableFor ?? this.stableFor,
    stable: stable ?? this.stable,
    requirement: requirement ?? this.requirement,
    updatedAt: updatedAt ?? this.updatedAt,
    hasSamples: hasSamples ?? this.hasSamples,
  );
}

/// 从加速度计采样计算稳定度。
///
/// 算法刻意保持简单、可测试：
/// 1. 相邻采样的加速度差作为手抖强度；
/// 2. 低于噪声地板的差值不计入，避免静止设备被误判为晃动；
/// 3. 指数平滑抑制单帧尖峰；
/// 4. 只有连续稳定达到阈值时长才标记为可拍摄。
class StabilityAnalyzer {
  StabilityAnalyzer({
    StabilityRequirement requirement = StabilityRequirement.standard,
    this.noiseFloor = .06,
    this.smoothing = .22,
    this.zeroScoreMotion = .6,
  }) : _requirement = requirement;

  /// 传感器噪声地板，低于该值的相邻差值不计入运动。
  final double noiseFloor;

  /// 新采样在平滑结果中的权重，越低越平滑但响应越慢。
  final double smoothing;

  /// 达到该运动强度时稳定度归零。
  final double zeroScoreMotion;

  StabilityRequirement _requirement;
  StabilitySnapshot _snapshot = const StabilitySnapshot.initial();
  ({double x, double y, double z})? _lastSample;
  DateTime? _stableSince;

  StabilitySnapshot get snapshot => _snapshot;

  StabilityRequirement get requirement => _requirement;

  /// 切换镜头或前后台恢复时调用，避免把上一段运动带入新会话。
  void reset() {
    _lastSample = null;
    _stableSince = null;
    _snapshot = const StabilitySnapshot.initial().copyWith(
      requirement: _requirement,
    );
  }

  void setRequirement(StabilityRequirement value) {
    if (value == _requirement) return;
    _requirement = value;
    _snapshot = _snapshot.copyWith(requirement: value);
    _recomputeStability(_snapshot.updatedAt ?? DateTime.now());
  }

  /// 摄入一个加速度计采样，返回新的稳定度快照。
  StabilitySnapshot ingest(
    double x,
    double y,
    double z, {
    DateTime? at,
  }) {
    final time = at ?? DateTime.now();
    final previous = _lastSample;
    _lastSample = (x: x, y: y, z: z);
    if (previous == null) {
      _stableSince = time;
      _snapshot = StabilitySnapshot(
        motion: 0,
        score: 100,
        stableFor: Duration.zero,
        stable: false,
        requirement: _requirement,
        updatedAt: time,
        hasSamples: true,
      );
      return _snapshot;
    }
    final delta = math.sqrt(
      math.pow(x - previous.x, 2) +
          math.pow(y - previous.y, 2) +
          math.pow(z - previous.z, 2),
    );
    final effective = delta <= noiseFloor ? 0.0 : delta - noiseFloor;
    final motion = _snapshot.motion * (1 - smoothing) + effective * smoothing;
    final score =
        (100 * (1 - (motion / zeroScoreMotion).clamp(0.0, 1.0))).toDouble();
    _snapshot = _snapshot.copyWith(
      motion: motion,
      score: score,
      updatedAt: time,
      hasSamples: true,
      requirement: _requirement,
    );
    _recomputeStability(time);
    return _snapshot;
  }

  void _recomputeStability(DateTime time) {
    if (_snapshot.motion > _requirement.maxMotion) {
      _stableSince = time;
    } else {
      _stableSince ??= time;
    }
    final stableSince = _stableSince ?? time;
    final stableFor = time.difference(stableSince);
    final stable =
        _snapshot.motion <= _requirement.maxMotion &&
        stableFor >= _requirement.minStableDuration;
    _snapshot = _snapshot.copyWith(stable: stable, stableFor: stableFor);
  }
}
