import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:ai_image_studio/features/share/presentation/share_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 草稿页:与收藏共用本地存储,语义上是"未发布/未完成"的作品。
/// 复用 _CollectionRow 渲染。
class DraftsPage extends ConsumerWidget {
  const DraftsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftsAsync = ref.watch(draftsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('草稿')),
      body: draftsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败:$e')),
        data: (ids) {
          if (ids.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_note, size: 56),
                    const SizedBox(height: 12),
                    Text('没有草稿',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('作品页点击"存为草稿"会出现在这里'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go('/history'),
                      child: const Text('去作品库'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ids.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final id = ids.elementAt(ids.length - 1 - index);
              return _DraftRow(taskId: id);
            },
          );
        },
      ),
    );
  }
}

class _DraftRow extends ConsumerWidget {
  const _DraftRow({required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailProvider(taskId));
    return Card(
      child: ListTile(
        title: taskAsync.maybeWhen(
          data: (t) => Text(t.prompt.isEmpty ? '(无提示词)' : t.prompt,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          orElse: () =>
              Text(taskId, style: Theme.of(context).textTheme.bodySmall),
        ),
        subtitle: taskAsync.maybeWhen(
          data: (t) => Text(t.status),
          orElse: () => const SizedBox.shrink(),
        ),
        trailing: Wrap(spacing: 0, children: [
          IconButton(
            tooltip: '继续创作',
            icon: const Icon(Icons.play_arrow_outlined),
            onPressed: () => context.push('/task/$taskId'),
          ),
          IconButton(
            tooltip: '移除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await ref.read(toggleDraftProvider)(taskId, false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已从草稿移除')),
                );
              }
            },
          ),
        ]),
      ),
    );
  }
}
