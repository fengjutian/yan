import 'dart:async';
import 'dart:io';

import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/core/widgets/creation_image.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/generate/data/local_creation_store.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_controller.dart';
import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:ai_image_studio/features/share/presentation/share_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({required this.taskId, super.key});
  final String taskId;
  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  Timer? _pollTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _schedulePoll();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final current = ref.read(taskDetailProvider(widget.taskId)).valueOrNull;
      if (current != null && current.isTerminal) return;
      ref.invalidate(taskDetailProvider(widget.taskId));
      _schedulePoll();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(taskDetailProvider(widget.taskId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('作品详情'),
        actions: [
          task.maybeWhen(
            data: (t) => Row(
              children: [
                IconButton(
                  tooltip: '收藏',
                  icon: const Icon(Icons.favorite_border),
                  onPressed: () => _toggleFavorite(t.id),
                ),
                IconButton(
                  tooltip: '存为草稿',
                  icon: const Icon(Icons.edit_note),
                  onPressed: () => _toggleDraft(t.id, true),
                ),
                if (t.isLocal)
                  IconButton(
                    tooltip: '删除作品',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteLocal(t.id),
                  ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(taskDetailProvider(widget.taskId));
          await ref.read(taskDetailProvider(widget.taskId).future);
        },
        child: task.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 120),
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 12),
              Center(child: Text('无法加载：${error.toString()}')),
            ],
          ),
          data: (value) => _buildData(value),
        ),
      ),
    );
  }

  Widget _buildData(dynamic value) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!value.isTerminal) ...[
          LinearProgressIndicator(value: value.progress / 100),
          const SizedBox(height: 8),
          Text('生成中 · ${value.progress}%'),
          const SizedBox(height: 16),
        ],
        for (final image in value.images)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: CreationImage(image: image),
                  ),
                  if (_isAiType(value.type))
                    const Positioned(
                      left: 12,
                      bottom: 12,
                      child: _AiWatermarkBadge(),
                    ),
                ],
              ),
            ),
          ),
        if (value.images.isEmpty && value.isTerminal)
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(child: Text('本次生成未产出图片')),
          ),
        if (value.status == 'FAILED') ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(value.isLocal ? '生成失败' : '生成失败，额度已退回'),
              subtitle: Text(value.errorMessage ?? '请稍后重试'),
              trailing: TextButton(
                onPressed: _busy ? null : () => _retry(value.id),
                child: const Text('重试'),
              ),
            ),
          ),
        ],
        Text(value.prompt, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(_typeLabel(value.type)),
        const SizedBox(height: 24),
        _ActionGrid(
          busy: _busy,
          onSave: () =>
              _save(value.images.isNotEmpty ? value.images.first : null),
          onShare: () =>
              _share(value.images.isNotEmpty ? value.images.first : null),
          onShareWorkshop: () =>
              context.push('/share?taskId=${Uri.encodeComponent(value.id)}'),
          onToggleDraft: () => _toggleDraft(value.id, true),
        ),
        const SizedBox(height: 16),
        _ParamsCard(task: value),
      ],
    );
  }

  bool _isAiType(String type) =>
      type == 'TEXT_TO_IMAGE' ||
      type == 'CHARACTER_REFERENCE' ||
      type == 'STYLE_TRANSFER';

  String _typeLabel(String type) => switch (type) {
    'CAMERA' => '相机作品',
    'EDIT' => '编辑作品',
    'STYLE_TRANSFER' => 'AI 风格迁移 · AI 生成',
    'CHARACTER_REFERENCE' => '人物参考创作 · AI 生成',
    _ => '文生图 · AI 生成',
  };

  Future<void> _toggleFavorite(String taskId) async {
    await ref.read(toggleFavoriteProvider)(taskId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('收藏已更新')));
  }

  Future<void> _toggleDraft(String taskId, bool add) async {
    await ref.read(toggleDraftProvider)(taskId, add);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(add ? '已存为草稿' : '已从草稿移除')));
  }

  Future<void> _retry(String taskId) async {
    setState(() => _busy = true);
    try {
      final replacement = await ref
          .read(generateRepositoryProvider)
          .retry(taskId);
      if (!mounted) return;
      context.pushReplacement('/task/${replacement.id}');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重试失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteLocal(String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除作品'),
        content: const Text('删除后本机图片和记录都会被移除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(localCreationStoreProvider).delete(taskId);
      try {
        final collections = ref.read(localCollectionServiceProvider);
        await collections.removeFavorite(taskId);
        await collections.removeDraft(taskId);
        ref.invalidate(favoritesProvider);
        ref.invalidate(draftsProvider);
      } catch (_) {
        // 收藏/草稿清理失败不应阻塞作品删除。
      }
      ref.invalidate(historyControllerProvider);
      if (!mounted) return;
      context.pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  Future<Uint8List?> _downloadImage(GeneratedImage image) =>
      loadCreationImageBytes(image);

  Future<void> _save(GeneratedImage? image) async {
    if (image == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _downloadImage(image);
      if (bytes == null) throw Exception('读取图片失败');
      final result = await SaverGallery.saveImage(
        bytes,
        fileName: 'yan-${DateTime.now().millisecondsSinceEpoch}',
        albumPath: 'Yan',
        skipIfExists: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess ? '已保存到相册' : '保存失败:${result.errorMessage}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败:$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(GeneratedImage? image) async {
    if (image == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _downloadImage(image);
      if (bytes == null) throw Exception('读取图片失败');
      final (extension, mimeType) = _imageFormat(bytes);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/yan-${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeType)],
        text: _valuePromptText(ref, widget.taskId),
        subject: _valuePromptText(ref, widget.taskId),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享失败:$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  (String, String) _imageFormat(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return ('.png', 'image/png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57) {
      return ('.webp', 'image/webp');
    }
    return ('.jpg', 'image/jpeg');
  }
}

String _valuePromptText(WidgetRef ref, String taskId) {
  final task = ref.read(taskDetailProvider(taskId));
  return task.maybeWhen(
    data: (t) => t.prompt.isEmpty ? '颜 · AI 生成' : t.prompt,
    orElse: () => '颜 · AI 生成',
  );
}

class _AiWatermarkBadge extends StatelessWidget {
  const _AiWatermarkBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome, size: 12, color: Colors.white),
        SizedBox(width: 4),
        Text('AI 生成', style: TextStyle(color: Colors.white, fontSize: 11)),
      ],
    ),
  );
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.busy,
    required this.onSave,
    required this.onShare,
    required this.onShareWorkshop,
    required this.onToggleDraft,
  });

  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onShareWorkshop;
  final VoidCallback onToggleDraft;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ActionButton(
          icon: Icons.share,
          label: '系统分享',
          busy: busy,
          onTap: onShare,
        ),
        _ActionButton(
          icon: Icons.auto_awesome_motion_outlined,
          label: '分享工作台',
          busy: busy,
          onTap: onShareWorkshop,
        ),
        _ActionButton(
          icon: Icons.download_outlined,
          label: '保存到相册',
          busy: busy,
          onTap: onSave,
        ),
        _ActionButton(
          icon: Icons.edit_note,
          label: '存为草稿',
          busy: busy,
          onTap: onToggleDraft,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}

class _ParamsCard extends StatelessWidget {
  const _ParamsCard({required this.task});
  final dynamic task;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('生成参数', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _kv(context, '任务 ID', task.id),
          _kv(context, '类型', task.type ?? 'TEXT_TO_IMAGE'),
          _kv(context, '创建时间', (task.createdAt ?? '').toString()),
          _kv(context, '提示词长度', '${task.prompt.toString().length} 字符'),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            k,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ),
        Expanded(child: Text(v, style: Theme.of(context).textTheme.bodySmall)),
      ],
    ),
  );
}
