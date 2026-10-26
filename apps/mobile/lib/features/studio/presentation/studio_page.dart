import 'dart:typed_data';

import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/core/widgets/creation_image.dart';
import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/history/presentation/creation_display.dart';
import 'package:ai_image_studio/features/history/presentation/recent_creations_controller.dart';
import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:ai_image_studio/features/templates/presentation/templates_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

/// 工作室:把「有照片 → 选创作方式 → 看到最近成果」收敛到一屏。
class StudioPage extends ConsumerStatefulWidget {
  const StudioPage({super.key});

  @override
  ConsumerState<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends ConsumerState<StudioPage> {
  bool _picking = false;

  Future<void> _refresh() async {
    ref.invalidate(recentCreationsProvider);
    ref.invalidate(featuredTemplatesProvider);
    await ref.read(recentCreationsProvider.future);
  }

  Future<Uint8List?> _pickPhoto() async {
    if (_picking) return null;
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 92,
      );
      if (file == null) return null;
      return file.readAsBytes();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('无法读取照片：$error')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _importAndChoose() async {
    final bytes = await _pickPhoto();
    if (bytes == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  '照片已选好',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const _SheetIcon(
                  icon: Icons.auto_awesome,
                  color: AppColors.rose,
                ),
                title: const Text('AI 风格迁移'),
                subtitle: const Text('保留人物特征，重塑画面氛围'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/style-transfer', extra: bytes);
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const _SheetIcon(
                  icon: Icons.tune,
                  color: Color(0xFF9A654F),
                ),
                title: const Text('图片编辑器'),
                subtitle: const Text('裁剪、旋转、亮度与色彩'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/editor', extra: bytes);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openStyleTransfer(Uint8List? bytes) {
    context.push('/style-transfer', extra: bytes);
  }

  void _openEditor(Uint8List? bytes) {
    context.push('/editor', extra: bytes);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cameraSessionProvider);
    final selected = session.selected;
    final recent = ref.watch(recentCreationsProvider);
    final templates = ref.watch(featuredTemplatesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作室'),
        actions: [
          IconButton(
            tooltip: '我的作品',
            icon: const Icon(Icons.collections_outlined),
            onPressed: () => context.push('/history'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
          children: [
            Text('让照片成为作品', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              selected == null ? '导入一张照片，或直接拍一张。' : '照片已就绪，挑一种方式继续。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            _CanvasCard(
              selected: selected,
              picking: _picking,
              onOpenStyleTransfer: () => _openStyleTransfer(selected?.bytes),
              onOpenEditor: () => _openEditor(selected?.bytes),
              onImport: _importAndChoose,
              onCamera: () => context.go('/camera'),
            ),
            if (session.photos.length > 1) ...[
              const SizedBox(height: 12),
              _CandidateStrip(
                photos: session.photos,
                selectedIndex: session.selectedIndex,
                onSelect: ref.read(cameraSessionProvider.notifier).select,
              ),
            ],
            const SizedBox(height: 24),
            _SectionHeader(
              title: '快捷工具',
              trailing: _picking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            _ToolGrid(
              onEdit: () => _openEditor(selected?.bytes),
              onImport: _importAndChoose,
              onCreate: () => context.push('/create/text-to-image'),
              onWorks: () => context.push('/history'),
            ),
            const SizedBox(height: 28),
            _RecentWorksSection(recent: recent),
            const SizedBox(height: 28),
            _TemplateSection(
              templates: templates,
              onOpen: (template) => context.push('/templates/${template.id}'),
              onSeeAll: () => context.push('/templates'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasCard extends StatelessWidget {
  const _CanvasCard({
    required this.selected,
    required this.picking,
    required this.onOpenStyleTransfer,
    required this.onOpenEditor,
    required this.onImport,
    required this.onCamera,
  });

  final CapturedPhoto? selected;
  final bool picking;
  final VoidCallback onOpenStyleTransfer;
  final VoidCallback onOpenEditor;
  final VoidCallback onImport;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(28);
    final photo = selected;

    if (photo == null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                AppColors.rose.withValues(alpha: .16),
                scheme.surface,
              ),
              scheme.surface,
            ],
          ),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.rose.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: AppColors.rose,
                    size: 26,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: const Text(
                    '本地处理',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              '先放一张照片进来',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '相册导入、相机成片都可以。原图只保存在本机。',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: picking ? null : onImport,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(picking ? '读取中…' : '从相册导入'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('去拍一张'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenStyleTransfer,
        borderRadius: radius,
        child: Ink(
          height: 250,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  photo.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: 1200,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Colors.black12,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x33000000),
                        Color(0x00000000),
                        Color(0xCC000000),
                      ],
                      stops: [0, .42, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '相机成片 · ${photo.qualityLabel} ${photo.score.round()} 分',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.black.withValues(alpha: .42),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: '编辑照片',
                      onPressed: onOpenEditor,
                      icon: const Icon(
                        Icons.tune,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'AI 风格迁移',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '保留人物特征，重塑画面氛围',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .82),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.ink,
                          size: 21,
                        ),
                      ),
                    ],
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

class _CandidateStrip extends StatelessWidget {
  const _CandidateStrip({
    required this.photos,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<CapturedPhoto> photos;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final active = index == selectedIndex;
          return GestureDetector(
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active
                      ? AppColors.rose
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: active ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      photos[index].bytes,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                    ),
                    if (active)
                      Container(color: AppColors.rose.withValues(alpha: .14)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToolGrid extends StatelessWidget {
  const _ToolGrid({
    required this.onEdit,
    required this.onImport,
    required this.onCreate,
    required this.onWorks,
  });

  final VoidCallback onEdit;
  final VoidCallback onImport;
  final VoidCallback onCreate;
  final VoidCallback onWorks;

  @override
  Widget build(BuildContext context) {
    final tools = [
      _Tool(
        icon: Icons.tune,
        title: '图片编辑器',
        subtitle: '裁剪 / 旋转 / 调色',
        color: const Color(0xFF9A654F),
        onTap: onEdit,
      ),
      _Tool(
        icon: Icons.add_photo_alternate_outlined,
        title: '导入照片',
        subtitle: '从相册选一张',
        color: const Color(0xFF52718D),
        onTap: onImport,
      ),
      _Tool(
        icon: Icons.draw_outlined,
        title: 'AI 图像创作',
        subtitle: '一句话生成画面',
        color: const Color(0xFF86669A),
        onTap: onCreate,
      ),
      _Tool(
        icon: Icons.collections_outlined,
        title: '我的作品',
        subtitle: '成片与历史版本',
        color: const Color(0xFF8A6A58),
        onTap: onWorks,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 112,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) => _ToolTile(tool: tools[index]),
    );
  }
}

class _Tool {
  const _Tool({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: tool.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tool.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(tool.icon, color: tool.color, size: 20),
              ),
              const Spacer(),
              Text(
                tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                tool.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentWorksSection extends StatelessWidget {
  const _RecentWorksSection({required this.recent});

  final AsyncValue<List<ImageTask>> recent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '最近作品',
          actionLabel: '全部作品',
          onAction: () => context.push('/history'),
        ),
        const SizedBox(height: 12),
        recent.when(
          loading: () => const SizedBox(
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _RecentEmpty(
            icon: Icons.folder_off_outlined,
            title: '本地作品读取失败',
            hint: '下拉重试，或检查应用存储权限。',
          ),
          data: (tasks) {
            if (tasks.isEmpty) {
              return const _RecentEmpty(
                icon: Icons.photo_library_outlined,
                title: '还没有作品',
                hint: '从上方导入照片或拍一张，成片会出现在这里。',
              );
            }
            return SizedBox(
              height: 164,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tasks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _RecentCard(task: tasks[index]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.task});

  final ImageTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = task.images.isEmpty ? null : task.images.first;
    return SizedBox(
      width: 116,
      child: InkWell(
        onTap: () => context.push('/task/${task.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 118,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image == null)
                    const Center(
                      child: Icon(Icons.image_not_supported_outlined),
                    )
                  else
                    CreationImage(image: image, preferThumbnail: true),
                  if (task.status != 'SUCCEEDED')
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          task.status == 'FAILED' ? '失败' : '处理中',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              creationTypeLabel(task.type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 1),
            Text(
              creationTimeLabel(task.createdAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentEmpty extends StatelessWidget {
  const _RecentEmpty({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateSection extends StatelessWidget {
  const _TemplateSection({
    required this.templates,
    required this.onOpen,
    required this.onSeeAll,
  });

  final AsyncValue<List<InspirationTemplate>> templates;
  final ValueChanged<InspirationTemplate> onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: '从灵感开始', actionLabel: '更多模板', onAction: onSeeAll),
        const SizedBox(height: 12),
        templates.when(
          loading: () => const SizedBox(
            height: 132,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (items) {
            if (items.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return InkWell(
                    onTap: () => onOpen(item),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 168,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            item.coverColor,
                            Color.lerp(item.coverColor, Colors.white, .55)!,
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            item.category.icon,
                            size: 22,
                            color: Colors.black54,
                          ),
                          const Spacer(),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xCC292725),
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        if (trailing != null) trailing!,
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: color, size: 22),
  );
}
