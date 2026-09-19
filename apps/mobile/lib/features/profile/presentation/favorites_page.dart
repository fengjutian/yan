import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_controller.dart';
import 'package:ai_image_studio/features/share/presentation/share_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 收藏�?本地保存�?taskId 集合,按时间倒序展示对应的历史作品�?/// MVP 没有单独接口,先复用历史接口按 ID �?后续�?/me/favorites�?class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favsAsync = ref.watch(favoritesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: favsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败:$e')),
        data: (ids) {
          if (ids.isEmpty) {
            return const _EmptyHint(text: '还没有收藏的作品');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ids.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final id = ids.elementAt(ids.length - 1 - index);
              return _FavoriteRow(taskId: id);
            },
          );
        },
      ),
    );
  }
}

class _FavoriteRow extends ConsumerWidget {
  const _FavoriteRow({required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailProvider(taskId));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/task/$taskId'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(
              width: 80,
              height: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: taskAsync.maybeWhen(
                  data: (t) {
                    final url = t.images.isNotEmpty ? t.images.first.thumbnailUrl : null;
                    if (url == null) {
                      return const ColoredBox(
                        color: Colors.black12,
                        child: Icon(Icons.image_not_supported_outlined),
                      );
                    }
                    return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover);
                  },
                  orElse: () => const ColoredBox(
                    color: Colors.black12,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  taskAsync.maybeWhen(
                    data: (t) => Text(
                      t.prompt.isEmpty ? '(无提示词)' : t.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    orElse: () => Text(
                      taskId,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  taskAsync.maybeWhen(
                    data: (t) => Text(t.status,
                        style: Theme.of(context).textTheme.bodySmall),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '取消收藏',
              icon: const Icon(Icons.favorite, color: Colors.redAccent),
              onPressed: () async {
                await ref.read(toggleFavoriteProvider)(taskId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已取消收�?)),
                  );
                }
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_border, size: 56),
              const SizedBox(height: 12),
              Text(text, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('在作品详情页点击 �?即可收藏'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/history'),
                child: const Text('去作品库看看'),
              ),
            ],
          ),
        ),
      );
}
