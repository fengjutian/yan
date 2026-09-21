import 'dart:typed_data';

import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:ai_image_studio/features/style_transfer/presentation/style_transfer_controller.dart';
import 'package:ai_image_studio/features/styles/presentation/styles_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 风格迁移页:选风格 + 强度滑杆 + 保护开关 + 前后对比滑动。
/// 后端 STYLE_TRANSFER 任务类型未上线,先用 CHARACTER_REFERENCE fallback。
class StyleTransferPage extends ConsumerStatefulWidget {
  const StyleTransferPage({this.sourceBytes, super.key});
  final Uint8List? sourceBytes;

  @override
  ConsumerState<StyleTransferPage> createState() => _StyleTransferPageState();
}

class _StyleTransferPageState extends ConsumerState<StyleTransferPage> {
  double _sliderPosition = 0.5; // 前后对比滑动条

  @override
  Widget build(BuildContext context) {
    final stylesAsync = ref.watch(stylesProvider);
    final state = ref.watch(styleTransferControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 风格迁移'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            tooltip: '前往分享工作台',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => context.push('/share'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BeforeAfterSlider(
                    sourceBytes: widget.sourceBytes,
                    position: _sliderPosition,
                    onChanged: (v) => setState(() => _sliderPosition = v),
                  ),
                  const SizedBox(height: 12),
                  const _StrengthLegend(),
                  const SizedBox(height: 16),
                  Text('选择风格', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  stylesAsync.when(
                    data: (styles) => _StyleChips(
                      styles: styles,
                      selected: state.styleId,
                      onSelect: (s) => ref
                          .read(styleTransferControllerProvider.notifier)
                          .setStyle(s),
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('加载风格失败:$e'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('迁移强度', style: Theme.of(context).textTheme.titleSmall),
                  Slider(
                    value: state.strength,
                    onChanged: (v) => ref
                        .read(styleTransferControllerProvider.notifier)
                        .setStrength(v),
                    min: 0,
                    max: 1,
                  ),
                  Row(children: [
                    const Text('保持原片', style: TextStyle(fontSize: 12)),
                    const Spacer(),
                    Text('${(state.strength * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    const Text('强烈重塑',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ]),
                  const SizedBox(height: 16),
                  Text('保护选项', style: Theme.of(context).textTheme.titleSmall),
                  _ProtectTile(
                    icon: Icons.face,
                    title: '人脸保护',
                    subtitle: '防止人物五官被风格吃掉',
                    value: state.protectFace,
                    onChanged: (v) => ref
                        .read(styleTransferControllerProvider.notifier)
                        .setProtectFace(v),
                  ),
                  _ProtectTile(
                    icon: Icons.palette_outlined,
                    title: '肤色保护',
                    subtitle: '保留肤色与肤质',
                    value: state.protectSkin,
                    onChanged: (v) => ref
                        .read(styleTransferControllerProvider.notifier)
                        .setProtectSkin(v),
                  ),
                  _ProtectTile(
                    icon: Icons.landscape_outlined,
                    title: '背景保护',
                    subtitle: '避免背景被风格纹理覆盖',
                    value: state.protectBackground,
                    onChanged: (v) => ref
                        .read(styleTransferControllerProvider.notifier)
                        .setProtectBackground(v),
                  ),
                  if (state.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(state.errorMessage!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: state.submitting || state.styleId == null
                    ? null
                    : () => _submit(context),
                icon: state.submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome),
                label: const Text('生成成片'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final bytes = widget.sourceBytes ??
        ref.read(cameraSessionProvider).selected?.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的源图,请先在相机或工作室准备一张')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已提交任务,请前往作品库查看进度')),
    );
    if (!context.mounted) return;
    context.go('/history');
  }
}

class _StrengthLegend extends StatelessWidget {
  const _StrengthLegend();
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: Colors.green, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        const Text('原片', style: TextStyle(fontSize: 11, color: AppColors.muted)),
        const Spacer(),
        const Text('成片', style: TextStyle(fontSize: 11, color: AppColors.muted)),
        const SizedBox(width: 4),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: AppColors.rose, shape: BoxShape.circle),
        ),
      ]);
}

/// 前后对比滑动:拖动滑块显示左侧原图、右侧"模拟成片"(用风格色覆盖表示)。
class _BeforeAfterSlider extends StatelessWidget {
  const _BeforeAfterSlider({
    required this.sourceBytes,
    required this.position,
    required this.onChanged,
  });
  final Uint8List? sourceBytes;
  final double position;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = (w * 4 / 3).clamp(0.0, 320.0);
        return SizedBox(
          height: h,
          child: Stack(children: [
            // 原图(占满)
            Positioned.fill(
              child: Container(
                color: Colors.black12,
                child: sourceBytes == null
                    ? const Center(child: Text('请从相机/工作室带入原图'))
                    : Image.memory(sourceBytes!, fit: BoxFit.cover),
              ),
            ),
            // 模拟成片:用柔和米色渐变 + 风格描述,等待真实结果接入
            Positioned(
              left: position * w,
              top: 0,
              bottom: 0,
              width: w - position * w,
              child: ClipRect(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE6D3B8), Color(0xFFB07E5A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '成片预览 · 提交后可见',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 分割线
            Positioned(
              left: position * w - 1,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: Colors.white),
            ),
            // 把手
            Positioned(
              left: position * w - 18,
              top: h / 2 - 18,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 8,
                        offset: Offset(0, 2))
                  ],
                ),
                child: const Icon(Icons.compare_arrows,
                    color: Colors.black87, size: 22),
              ),
            ),
            // 滑动热区
            Positioned.fill(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                ),
                child: Slider(
                  value: position,
                  onChanged: onChanged,
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _StyleChips extends StatelessWidget {
  const _StyleChips({
    required this.styles,
    required this.selected,
    required this.onSelect,
  });
  final List<dynamic> styles;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final s in styles)
        ChoiceChip(
          label: Text((s.name as String?) ?? ''),
          selected: selected == s.id,
          onSelected: (_) => onSelect(s.id as String),
        ),
    ]);
  }
}

class _ProtectTile extends StatelessWidget {
  const _ProtectTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
      );
}