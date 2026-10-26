/// 作品类型在界面上的简短名称。
String creationTypeLabel(String type) => switch (type) {
  'STYLE_TRANSFER' => '风格迁移',
  'IMAGE_EDIT' => '图片编辑',
  'CHARACTER_REFERENCE' => '人物参考',
  'TEXT_TO_IMAGE' => 'AI 创作',
  _ => '作品',
};

/// 把创建时间渲染成适合卡片展示的相对时间。
///
/// [now] 仅用于测试注入,生产环境使用当前时间。
String creationTimeLabel(DateTime? createdAt, {DateTime? now}) {
  if (createdAt == null) return '';
  final local = createdAt.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (diff == 0) return '今天 $hh:$mm';
  if (diff == 1) return '昨天 $hh:$mm';
  if (local.year == current.year) return '${local.month} 月 ${local.day} 日';
  return '${local.year}.${local.month}.${local.day}';
}
