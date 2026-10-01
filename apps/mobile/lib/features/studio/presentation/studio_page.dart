import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class StudioPage extends ConsumerWidget {
  const StudioPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captured = ref.watch(cameraSessionProvider).selected;
    return Scaffold(
      appBar: AppBar(title: const Text('工作室')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('让照片成为作品', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            '导入照片，选择适合它的创作方式。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (captured != null) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  Image.memory(
                    captured.bytes,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '相机成片 · 质量 ${captured.score.round()} 分',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 26),
          _StudioCard(
            icon: Icons.auto_fix_high,
            title: 'AI 风格迁移',
            subtitle: '保留人物特征，重塑画面氛围',
            accent: const Color(0xFF32796D),
            badge: 'AI 推荐',
            featured: true,
            onTap: () =>
                context.push('/style-transfer', extra: captured?.bytes),
          ),
          const SizedBox(height: 12),
          _StudioCard(
            icon: Icons.tune,
            title: '图片编辑器',
            subtitle: '裁剪/旋转/调色，本地即时处理',
            accent: const Color(0xFF9A654F),
            onTap: () => context.push('/editor', extra: captured?.bytes),
          ),
          const SizedBox(height: 12),
          _StudioCard(
            icon: Icons.add_photo_alternate_outlined,
            title: '导入照片',
            subtitle: '上传原图并开始编辑',
            accent: const Color(0xFF52718D),
            onTap: () => context.push('/assets/upload'),
          ),
          const SizedBox(height: 12),
          _StudioCard(
            icon: Icons.draw_outlined,
            title: 'AI 图像创作',
            subtitle: '用一句话创造全新画面',
            accent: const Color(0xFF86669A),
            badge: 'AI',
            onTap: () => context.push('/create/text-to-image'),
          ),
          const SizedBox(height: 12),
          _StudioCard(
            icon: Icons.collections_outlined,
            title: '我的作品',
            subtitle: '查看成片与历史版本',
            accent: const Color(0xFF8A6A58),
            onTap: () => context.push('/history'),
          ),
          const SizedBox(height: 12),
          _StudioCard(
            icon: Icons.share_outlined,
            title: '分享工作台',
            subtitle: '平台裁剪 / AI 文案 / 一键分享',
            accent: const Color(0xFF4F786C),
            onTap: () => context.push('/share'),
          ),
        ],
      ),
    );
  }
}

class _StudioCard extends StatelessWidget {
  const _StudioCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.badge,
    this.featured = false,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String? badge;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: featured
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    accent.withValues(alpha: .14),
                    scheme.surface,
                  ),
                  scheme.surface,
                ],
              )
            : null,
        color: featured ? null : scheme.surface,
        border: Border.all(
          color: featured
              ? accent.withValues(alpha: isDark ? .50 : .24)
              : scheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? .16 : .055),
            blurRadius: featured ? 22 : 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: accent.withValues(alpha: .10),
          highlightColor: accent.withValues(alpha: .05),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 18,
              vertical: featured ? 21 : 18,
            ),
            child: Row(
              children: [
                Container(
                  width: featured ? 58 : 54,
                  height: featured ? 58 : 54,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? .22 : .11),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withValues(alpha: .10)),
                  ),
                  child: Icon(icon, color: accent, size: featured ? 28 : 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: featured ? 17 : 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.2,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .11),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: featured
                        ? accent
                        : accent.withValues(alpha: isDark ? .18 : .08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 19,
                    color: featured ? Colors.white : accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
