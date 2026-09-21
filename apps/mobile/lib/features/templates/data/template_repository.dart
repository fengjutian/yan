import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:flutter/material.dart' show Color, Offset;

/// 灵感模板仓库:内置 mock 数据(后端 /templates 接口起来后切换到 dio)。
class TemplateRepository {
  TemplateRepository();

  Future<List<InspirationTemplate>> listByCategory(
      [TemplateCategory? category]) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final all = _mock;
    if (category == null) return all;
    return all.where((t) => t.category == category).toList();
  }

  Future<InspirationTemplate?> findById(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    for (final t in _mock) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<List<InspirationTemplate>> featured() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final sorted = [..._mock]
      ..sort((a, b) => b.popularity.compareTo(a.popularity));
    return sorted.take(6).toList();
  }
}

final _mock = <InspirationTemplate>[
  // ── 人像写真 ─────────────────────────────────────────────
  InspirationTemplate(
    id: 'portrait_window',
    title: '窗边柔光人像',
    subtitle: '下午 4 点的窗光，让皮肤透亮',
    category: TemplateCategory.portrait,
    coverColor: const Color(0xFFF1D8C2),
    examplePrompt: '窗边少女侧脸,自然柔光,胶片色调,富士色调,温柔氛围',
    compositionRule: CompositionRule.thirds,
    cameraAngle: CameraAngle.eyeLevel,
    subjectPosition: const Offset(0.36, 0.45),
    standingTip: '靠近窗框 30cm,让侧光勾出脸部和头发的轮廓',
    recommendedStyles: ['film-soft', 'cream-portrait'],
    tags: ['侧脸', '柔光', '胶片'],
    popularity: 980,
  ),
  InspirationTemplate(
    id: 'portrait_cafe',
    title: '咖啡馆随拍',
    subtitle: '一杯咖啡 + 一束光',
    category: TemplateCategory.portrait,
    coverColor: const Color(0xFFE8C9B7),
    examplePrompt: '咖啡馆内女生手持马克杯,暖色调,真实光线,生活方式',
    compositionRule: CompositionRule.center,
    cameraAngle: CameraAngle.eyeLevel,
    subjectPosition: const Offset(0.5, 0.55),
    standingTip: '背对大窗,前景杯子可压低机位平拍',
    recommendedStyles: ['lifestyle', 'cafe-warm'],
    tags: ['咖啡', '随拍'],
    popularity: 760,
  ),

  // ── 旅行打卡 ─────────────────────────────────────────────
  InspirationTemplate(
    id: 'travel_skyline',
    title: '城市天际线',
    subtitle: '蓝调时刻的城市轮廓',
    category: TemplateCategory.travel,
    coverColor: const Color(0xFFB6C5D6),
    examplePrompt: '黄昏蓝调时刻,远处城市天际线,前景人物剪影,旅行电影感',
    compositionRule: CompositionRule.thirds,
    cameraAngle: CameraAngle.eyeLevel,
    subjectPosition: const Offset(0.3, 0.65),
    standingTip: '日落后 20-30 分钟最稳,人物站画面 1/3 处',
    recommendedStyles: ['cinematic-blue', 'travel-cine'],
    tags: ['天际线', '蓝调'],
    popularity: 1200,
  ),
  InspirationTemplate(
    id: 'travel_alley',
    title: '老街小巷',
    subtitle: '午后的斜影与门窗',
    category: TemplateCategory.travel,
    coverColor: const Color(0xFFE6C9A1),
    examplePrompt: '老街巷子,午后斜阳,人物靠墙,胶片颗粒,生活记录',
    compositionRule: CompositionRule.leadingLine,
    cameraAngle: CameraAngle.highAngle,
    subjectPosition: const Offset(0.7, 0.4),
    standingTip: '站在巷尾用延伸感引向人物,背景留出纵深',
    recommendedStyles: ['film-warm'],
    tags: ['老街', '光影'],
    popularity: 540,
  ),

  // ── 探店日常 ─────────────────────────────────────────────
  InspirationTemplate(
    id: 'explore_signage',
    title: '店铺招牌合影',
    subtitle: '招牌占顶,人物占下',
    category: TemplateCategory.explore,
    coverColor: const Color(0xFFEAB9AA),
    examplePrompt: '探店打卡照,人物站在店铺门口,招牌文字清晰,生活感',
    compositionRule: CompositionRule.frame,
    cameraAngle: CameraAngle.lowAngle,
    subjectPosition: const Offset(0.5, 0.7),
    standingTip: '招牌占画面上方 1/3,人物居中,低机位让人像挺拔',
    recommendedStyles: ['lifestyle'],
    tags: ['探店', '合影'],
    popularity: 670,
  ),

  // ── 美食静物 ─────────────────────────────────────────────
  InspirationTemplate(
    id: 'food_top',
    title: '俯拍一桌好菜',
    subtitle: '45° 角俯拍,光从左后',
    category: TemplateCategory.food,
    coverColor: const Color(0xFFE6BFA1),
    examplePrompt: '俯拍一桌家常菜,木质桌面,自然光,温暖色调,真实食物',
    compositionRule: CompositionRule.thirds,
    cameraAngle: CameraAngle.topDown,
    subjectPosition: const Offset(0.5, 0.5),
    standingTip: '主菜放画面中心,配菜分点状环绕,留出 1/3 桌面空白',
    recommendedStyles: ['food-warm'],
    tags: ['美食', '俯拍'],
    popularity: 430,
  ),
  InspirationTemplate(
    id: 'food_45',
    title: '45° 美食特写',
    subtitle: '前低后高,展现层次',
    category: TemplateCategory.food,
    coverColor: const Color(0xFFD7AE8E),
    examplePrompt: '近景美食特写,45° 视角,木质背景,自然光,精致摆盘',
    compositionRule: CompositionRule.thirds,
    cameraAngle: CameraAngle.highAngle,
    subjectPosition: const Offset(0.42, 0.55),
    standingTip: '前低后高堆叠餐具,主菜占前景,光线从左后方 45° 打',
    recommendedStyles: ['food-clean'],
    tags: ['美食', '特写'],
    popularity: 380,
  ),

  // ── 宠物生活 ─────────────────────────────────────────────
  InspirationTemplate(
    id: 'pet_floor',
    title: '地板上的伙伴',
    subtitle: '平行机位,记录眼神',
    category: TemplateCategory.pet,
    coverColor: const Color(0xFFB7D5C5),
    examplePrompt: '宠物趴在地上的近景,平行机位,自然光,真实质感',
    compositionRule: CompositionRule.center,
    cameraAngle: CameraAngle.lowAngle,
    subjectPosition: const Offset(0.5, 0.5),
    standingTip: '趴下与宠物同高,逆光抓耳朵边的毛',
    recommendedStyles: ['life-soft'],
    tags: ['宠物', '眼神'],
    popularity: 880,
  ),
];
