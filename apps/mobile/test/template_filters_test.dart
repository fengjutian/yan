import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:ai_image_studio/features/templates/presentation/template_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

InspirationTemplate _template({
  required String id,
  required String title,
  required TemplateCategory category,
  required int popularity,
  List<String> tags = const [],
  List<String> styles = const [],
  String subtitle = '',
}) => InspirationTemplate(
  id: id,
  title: title,
  subtitle: subtitle,
  category: category,
  coverColor: const Color(0xFFE8D5C4),
  examplePrompt: '',
  compositionRule: CompositionRule.thirds,
  cameraAngle: CameraAngle.eyeLevel,
  subjectPosition: const Offset(.5, .5),
  standingTip: '',
  recommendedStyles: styles,
  tags: tags,
  popularity: popularity,
);

void main() {
  final templates = [
    _template(
      id: 'portrait',
      title: '窗边柔光人像',
      subtitle: '下午四点的光',
      category: TemplateCategory.portrait,
      popularity: 980,
      tags: ['侧脸', '柔光'],
      styles: ['film-soft'],
    ),
    _template(
      id: 'travel',
      title: '城市天际线',
      subtitle: '蓝调时刻',
      category: TemplateCategory.travel,
      popularity: 1200,
      tags: ['天际线'],
      styles: ['cinematic-blue'],
    ),
    _template(
      id: 'food',
      title: '俯拍一桌好菜',
      subtitle: '45 度角',
      category: TemplateCategory.food,
      popularity: 430,
      tags: ['美食'],
      styles: ['food-warm'],
    ),
  ];

  test('按分类过滤', () {
    final result = filterTemplates(
      templates,
      category: TemplateCategory.travel,
    );
    expect(result.map((t) => t.id), ['travel']);
  });

  test('按标题、标签和推荐风格搜索', () {
    expect(filterTemplates(templates, query: '柔光').map((t) => t.id), [
      'portrait',
    ]);
    expect(filterTemplates(templates, query: '天际线').map((t) => t.id), [
      'travel',
    ]);
    expect(filterTemplates(templates, query: 'food-warm').map((t) => t.id), [
      'food',
    ]);
  });

  test('搜索不区分大小写并忽略首尾空格', () {
    final result = filterTemplates(templates, query: '  FILM-SOFT  ');
    expect(result.map((t) => t.id), ['portrait']);
  });

  test('按热度排序', () {
    final result = filterTemplates(templates, sort: TemplateSort.popular);
    expect(result.map((t) => t.id), ['travel', 'portrait', 'food']);
  });

  test('收藏模板排在前面', () {
    final result = filterTemplates(
      templates,
      sort: TemplateSort.favorites,
      favorites: {'food'},
    );
    expect(result.first.id, 'food');
  });

  test('推荐排序保持仓库原始顺序', () {
    final result = filterTemplates(templates);
    expect(result.map((t) => t.id), ['portrait', 'travel', 'food']);
  });
}
