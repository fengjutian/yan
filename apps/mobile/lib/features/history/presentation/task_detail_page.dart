import 'dart:async';
import 'dart:io';

import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:ai_image_studio/features/share/presentation/share_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
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
    _pollTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      ref.invalidate(taskDetailProvider(widget.taskId));
      final current = ref.read(taskDetailProvider(widget.taskId));
      final isDone = current.maybeWhen(
        data: (t) => t.isTerminal,
        orElse: () => false,
      );
      if (!isDone && mounted) _schedulePoll();
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
            data: (t) => Row(children: [
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
            ]),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(taskDetailProvider(widget.taskId));
        },
        child: task.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(children: [
            const SizedBox(height: 120),
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 12),
            Center(child: Text('无法加载：${error.toString()}')),
          ]),
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
              child: Stack(children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
                    imageUrl: image.url,
                    fit: BoxFit.cover,
                  ),
                ),
                const Positioned(
                  left: 12,
                  bottom: 12,
                  child: _AiWatermarkBadge(),
                ),
              ]),
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
        Text(value.prompt, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(value.type == 'CHARACTER_REFERENCE'
            ? '人物参考创作 · AI 生成'
            : '文生图 · AI 生成'),
        const SizedBox(height: 24),
        _ActionGrid(
          busy: _busy,
          onSave: () =>
              _save(value.images.isNotEmpty ? value.images.first.url : null),
          onShare: () =>
              _share(value.images.isNotEmpty ? value.images.first.url : null),
          onShareWorkshop: () =>
              context.push('/share?taskId=${Uri.encodeComponent(value.id)}'),
          onToggleDraft: () => _toggleDraft(value.id, true),
        ),
        const SizedBox(height: 16),
        _ParamsCard(task: value),
      ],
    );
  }

  Future<void> _toggleFavorite(String taskId) async {
    await ref.read(toggleFavoriteProvider)(taskId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('收藏已更新')),
    );
  }

  Future<void> _toggleDraft(String taskId, bool add) async {
    await ref.read(toggleDraftProvider)(taskId, add);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(add ? '已存为草稿' : '已从草稿移除')),
    );
  }

  Future<Uint8List?> _downloadImage(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    return response.bodyBytes;
  }

  Future<void> _save(String? url) async {
    if (url == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _downloadImage(url);
      if (bytes == null) throw Exception('下载图片失败');
      final result = await SaverGallery.saveImage(
        bytes,
        fileName: 'yan-${DateTime.now().millisecondsSinceEpoch}',
        albumPath: 'Yan',
        skipIfExists: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(result.isSuccess ? '已保存到相册' : '保存失败:${result.errorMessage}'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败:$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String? url) async {
    if (url == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _downloadImage(url);
      if (bytes == null) throw Exception('下载图片失败');
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/yan-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/jpeg')],
        text: _valuePromptText(ref, widget.taskId),
        subject: _valuePromptText(ref, widget.taskId),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('分享失败:$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: 12, color: Colors.white),
          SizedBox(width: 4),
          Text('AI 生成', style: TextStyle(color: Colors.white, fontSize: 11)),
        ]),
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
                child: CircularProgressIndicator(strokeWidth: 2))
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
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 80,
              child: Text(k,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.muted))),
          Expanded(
              child: Text(v, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}
