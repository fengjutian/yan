import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:ai_image_studio/features/templates/presentation/templates_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 模板详情:
/// 封面 + 机位 / 构图 / 站位 / 推荐风格 / 推荐文案 + "用此模板拍" 跳相机。
class TemplateDetailPage extends ConsumerWidget {
  const TemplateDetailPage({required this.templateId, super.key});
  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncT = ref.watch(templateByIdProvider(templateId));
    final favorites = ref.watch(templateFavoritesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('模板详情'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          asyncT.maybeWhen(
            data: (t) => IconButton(
              tooltip: favorites.contains(templateId) ? '取消收藏' : '收藏',
              icon: Icon(
                favorites.contains(templateId)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: favorites.contains(templateId) ? Colors.redAccent : null,
              ),
              onPressed: () => ref
                  .read(templateFavoritesProvider.notifier)
                  .toggle(templateId),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: asyncT.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败:$e')),
        data: (t) {
          if (t == null) {
            return const Center(child: Text('模板不存在'));
          }
          return _Body(t: t);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.t});
  final InspirationTemplate t;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [t.coverColor, Color.lerp(t.coverColor, Colors.white, .4)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Icon(t.category.icon, size: 64, color: Colors.black54),
          ),
        ),
        const SizedBox(height: 20),
        Text(t.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(t.subtitle,
            style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final tag in t.tags) Chip(label: Text(tag)),
        ]),
        const SizedBox(height: 24),
        _SectionTitle('构图与机位'),
        _InfoRow(
          icon: t.compositionRule.icon,
          label: '构图',
          value: t.compositionRule.label,
        ),
        _InfoRow(
          icon: Icons.straighten,
          label: '机位',
          value: t.cameraAngle.label,
        ),
        _InfoRow(
          icon: Icons.center_focus_weak,
          label: '主体位置',
          value:
              '水平 ${(t.subjectPosition.dx * 100).round()}% / 垂直 ${(t.subjectPosition.dy * 100).round()}%',
        ),
        _InfoRow(
          icon: Icons.directions_walk,
          label: '站位建议',
          value: t.standingTip,
          expanded: true,
        ),
        const SizedBox(height: 24),
        _SectionTitle('推荐风格'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in t.recommendedStyles) Chip(label: Text(s)),
        ]),
        const SizedBox(height: 24),
        _SectionTitle('示例 Prompt'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SelectableText(t.examplePrompt,
              style: const TextStyle(fontSize: 13, height: 1.5)),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('用此模板拍'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
          ),
          onPressed: () {
            context.push('/camera', extra: {
              'templateId': t.id,
              'prompt': t.examplePrompt,
              'composition': t.compositionRule.name,
              'angle': t.cameraAngle.name,
            });
          },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.expanded = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        expanded ? FontWeight.w500 : FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}