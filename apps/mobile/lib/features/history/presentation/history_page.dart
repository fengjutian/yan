import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({this.loadOnStart = true, super.key});
  final bool loadOnStart;
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnStart) {
      Future<void>.microtask(
          () => ref.read(historyControllerProvider.notifier).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(historyControllerProvider);
    final notifier = ref.read(historyControllerProvider.notifier);
    Widget child;
    if (state.tasks.isEmpty && state.loading) {
      child = const Center(child: CircularProgressIndicator());
    } else if (state.tasks.isEmpty) {
      child = ListView(
        children: const [
          SizedBox(height: 180),
          Icon(Icons.photo_library_outlined, size: 56),
          SizedBox(height: 12),
          Center(child: Text('还没有作品，开始第一次创作吧')),
        ],
      );
    } else {
      child = GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: state.tasks.length + (state.nextCursor.isNotEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.tasks.length) {
            // 仅当未在加载且有下一页时才触发,避免 itemBuilder 每次 rebuild 都触发。
            if (!state.loading) notifier.loadMore();
            return const Center(child: CircularProgressIndicator());
          }
          final task = state.tasks[index];
          final image = task.images.isEmpty ? null : task.images.first;
          return InkWell(
            onTap: () => context.push('/task/${task.id}'),
            borderRadius: BorderRadius.circular(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: image == null
                  ? const ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.image_not_supported_outlined),
                    )
                  : CachedNetworkImage(
                      imageUrl: image.thumbnailUrl,
                      fit: BoxFit.cover,
                    ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('我的作品')),
      body: RefreshIndicator(onRefresh: notifier.refresh, child: child),
    );
  }
}
