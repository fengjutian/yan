import 'dart:async';

import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({required this.taskId, super.key});
  final String taskId;
  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _schedulePoll();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      // 强制 invalidate FutureProvider 重新拉取
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
      appBar: AppBar(title: const Text('作品详情')),
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
          data: (value) => ListView(
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
                    child: CachedNetworkImage(
                      imageUrl: image.url,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              Text(value.prompt,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(value.type == 'CHARACTER_REFERENCE'
                  ? '人物参考创作 · AI 生成'
                  : '文生图 · AI 生成'),
            ],
          ),
        ),
      ),
    );
  }
}
