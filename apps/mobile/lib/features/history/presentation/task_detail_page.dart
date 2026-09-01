import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TaskDetailPage extends ConsumerWidget {
  const TaskDetailPage({required this.taskId, super.key});
  final String taskId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskDetailProvider(taskId));
    return Scaffold(
      appBar: AppBar(title: const Text('作品详情')),
      body: task.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (value) => ListView(padding: const EdgeInsets.all(20), children: [
          for (final image in value.images)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: CachedNetworkImage(
                      imageUrl: image.url, fit: BoxFit.contain)),
            ),
          Text(value.prompt, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(value.type == 'CHARACTER_REFERENCE'
              ? '人物参考创作 · AI 生成'
              : '文生图 · AI 生成'),
        ]),
      ),
    );
  }
}
