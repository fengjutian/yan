import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Color, IconData, Icons;

/// 灵感模板分类,对应 PRD 5.1.1。
enum TemplateCategory {
  portrait('人像写真', Icons.face_retouching_natural),
  travel('旅行打卡', Icons.flight_takeoff),
  explore('探店日常', Icons.storefront),
  food('美食静物', Icons.restaurant),
  pet('宠物生活', Icons.pets);

  const TemplateCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 机位(俯仰/平视/仰拍)。
enum CameraAngle {
  eyeLevel('平视', 0.0),
  lowAngle('低机位仰拍', 0.4),
  highAngle('高机位俯拍', -0.4),
  topDown('正俯拍', -0.9),
  dutch('倾斜构图', 0.15);

  const CameraAngle(this.label, this.tilt);
  final String label;
  final double tilt;
}

/// 三分构图规则。
enum CompositionRule {
  thirds('三分构图', Icons.grid_3x3),
  center('中心构图', Icons.center_focus_strong),
  symmetry('对称构图', Icons.flip),
  leadingLine('引导线', Icons.timeline),
  frame('框中框', Icons.crop_square);

  const CompositionRule(this.label, this.icon);
  final String label;
  final IconData icon;
}

@immutable
class InspirationTemplate {
  const InspirationTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.coverColor,
    required this.examplePrompt,
    required this.compositionRule,
    required this.cameraAngle,
    required this.subjectPosition,
    required this.standingTip,
    required this.recommendedStyles,
    required this.tags,
    this.popularity = 0,
  });

  final String id;
  final String title;
  final String subtitle;
  final TemplateCategory category;

  /// 卡片封面渐变基色(没图也能撑住视觉)。
  final Color coverColor;

  /// "用此模板拍" 跳相机时携带的初始 prompt。
  final String examplePrompt;

  final CompositionRule compositionRule;
  final CameraAngle cameraAngle;

  /// 主体在画面里的相对位置(0..1)。
  final Offset subjectPosition;
  final String standingTip;

  /// 推荐风格 id 列表,跳到创作页时预选。
  final List<String> recommendedStyles;
  final List<String> tags;

  final int popularity;

  factory InspirationTemplate.fromJson(Map<String, dynamic> json) =>
      InspirationTemplate(
        id: (json['id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        subtitle: (json['subtitle'] as String?) ?? '',
        category: _categoryFromString((json['category'] as String?) ?? ''),
        coverColor: _colorFromHex((json['cover_color'] as String?) ?? '#E6D3B8'),
        examplePrompt: (json['example_prompt'] as String?) ?? '',
        compositionRule:
            _compositionFromString((json['composition'] as String?) ?? ''),
        cameraAngle: _angleFromString((json['angle'] as String?) ?? ''),
        subjectPosition: Offset(
          ((json['subject_x'] as num?) ?? 0.5).toDouble(),
          ((json['subject_y'] as num?) ?? 0.5).toDouble(),
        ),
        standingTip: (json['standing_tip'] as String?) ?? '',
        recommendedStyles: ((json['styles'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .toList(),
        tags: ((json['tags'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .toList(),
        popularity: (json['popularity'] is num)
            ? (json['popularity'] as num).round()
            : 0,
      );
}

TemplateCategory _categoryFromString(String s) =>
    TemplateCategory.values.firstWhere(
      (c) => c.name == s,
      orElse: () => TemplateCategory.portrait,
    );

CompositionRule _compositionFromString(String s) =>
    CompositionRule.values.firstWhere(
      (c) => c.name == s,
      orElse: () => CompositionRule.thirds,
    );

CameraAngle _angleFromString(String s) => CameraAngle.values.firstWhere(
      (c) => c.name == s,
      orElse: () => CameraAngle.eyeLevel,
    );

Color _colorFromHex(String hex) {
  var v = hex.replaceFirst('#', '');
  if (v.length == 6) v = 'FF$v';
  final intVal = int.tryParse(v, radix: 16) ?? 0xFFE6D3B8;
  return Color(intVal);
}

/// 用户对模板的偏好(收藏)。
class TemplatePreference {
  const TemplatePreference({this.favorites = const {}});
  final Set<String> favorites;

  TemplatePreference copyWith({Set<String>? favorites}) =>
      TemplatePreference(favorites: favorites ?? this.favorites);
}