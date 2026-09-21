import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:ai_image_studio/features/share/presentation/share_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 收藏页:本地保存的 taskId 集合,按时间倒序展示对应的历史作品。
/// MVP 没有单独接口,先复用历史接口按 ID 拉,后续接 /me/favorites。
class FavoritesPage extends ConsumerWidget {
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
            return const _EmptyHint(
              icon: Icons.favorite_border,
              title: '还没有收藏的作品',
              hint: '在作品详情页点击 ♥ 即可收藏',
              actionLabel: '去作品库看看',
              actionRoute: '/history',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ids.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final id = ids.elementAt(ids.length - 1 - index);
              return _CollectionRow(taskId: id, kind: _RowKind.favorite);
            },
          );
        },
      ),
    );
  }
}

enum _RowKind { favorite }

class _CollectionRow extends ConsumerWidget {
  const _CollectionRow({required this.taskId, required this.kind});
  final String taskId;
  final _RowKind kind;

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
                    final url = t.images.isNotEmpty
                        ? t.images.first.thumbnailUrl
                        : null;
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
              tooltip: kind == _RowKind.favorite ? '取消收藏' : '从草稿移除',
              icon: Icon(
                kind == _RowKind.favorite ? Icons.favorite : Icons.edit_note,
                color: kind == _RowKind.favorite
                    ? Colors.redAccent
                    : Colors.blueAccent,
              ),
              onPressed: () async {
                if (kind == _RowKind.favorite) {
                  await ref.read(toggleFavoriteProvider)(taskId);
                } else {
                  await ref.read(toggleDraftProvider)(taskId, false);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(kind == _RowKind.favorite ? '已取消收藏' : '已从草稿移除'),
                  ));
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
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.actionRoute,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String actionLabel;
  final String actionRoute;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(hint),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(actionRoute),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
}
