import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:flutter/material.dart' show Color, Offset;

/// 灵感模板仓库:内置 mock 数据(后端 /templates 接口起来后切换到 dio)。
class TemplateRepository {
  TemplateRepository();

  Future<List<InspirationTemplate>> listByCategory([
    TemplateCategory? category,
  ]) async {
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
    examplePrompt:
        '一位年轻女生靠近窗边微微侧脸，下午四点的自然光从侧后方照入，勾亮发丝与面部轮廓，肤色通透自然。三分构图，半身人像，浅景深，柔和胶片质感，奶油色调，细腻颗粒，安静温柔的居家氛围。',
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
    examplePrompt:
        '暖色咖啡馆内，一位女生自然地手持马克杯望向窗外，窗边柔光落在面部，桌面与咖啡杯作为前景。平视半身构图，真实肤质，浅景深，背景轻微虚化，温暖克制的生活方式摄影，自然抓拍感。',
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
    examplePrompt:
        '日落后蓝调时刻，远处城市天际线亮起零星灯光，天空由深蓝过渡到冷灰蓝。一位旅行者站在画面左侧三分线、占画面约 1/3，形成清晰但保留细节的前景剪影。平视广角构图，城市纵深明显，冷暖光影对比，电影级色彩，轻微胶片颗粒，真实旅行摄影，高细节。',
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
    examplePrompt:
        '午后斜阳穿过老街窄巷，在墙面留下长条光影，一位旅行者自然靠墙站立。利用巷道形成引导线，人物位于右侧三分线，背景保留门窗与生活痕迹，暖色胶片质感，细腻颗粒，低饱和，真实纪实抓拍。',
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
    examplePrompt:
        '街角店铺门口的探店合影，完整保留上方招牌，人物自然站在画面下方中央。略低机位，轻微广角，建筑线条端正，招牌清晰可辨，柔和自然光，肤色真实，轻松松弛的生活感，干净有层次的街拍画面。',
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
    examplePrompt:
        '正上方俯拍一桌丰盛家常菜，主菜居中，配菜与餐具疏密有致地环绕，保留约 1/3 木质桌面作为留白。左后方自然窗光，食物色泽真实诱人，暖色调不过饱和，纹理清晰，轻微阴影，高级美食杂志摄影。',
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
    examplePrompt:
        '以 45° 视角拍摄精致摆盘的近景美食，主菜位于左侧三分线，前景餐具轻微虚化，背景层次自然。左后方柔和窗光勾勒食物纹理，木质桌面，真实色泽，干净暖调，浅景深，商业美食摄影质感。',
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
    examplePrompt:
        '镜头贴近地面，与趴着的宠物保持同一视线高度，准确捕捉明亮眼神。自然逆光勾亮耳朵和毛发边缘，主体居中，近景构图，浅景深，背景柔和虚化，毛发细节清晰，色彩自然，温暖真实的生活记录。',
    compositionRule: CompositionRule.center,
    cameraAngle: CameraAngle.lowAngle,
    subjectPosition: const Offset(0.5, 0.5),
    standingTip: '趴下与宠物同高,逆光抓耳朵边的毛',
    recommendedStyles: ['life-soft'],
    tags: ['宠物', '眼神'],
    popularity: 880,
  ),
];
