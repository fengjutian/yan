import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/generate/data/local_creation_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 最近作品:灵感首页和工作室共用。
///
/// 使用 autoDispose,离开页面后释放;再次进入会重新读取本地作品库,
/// 因此从编辑器/生成页返回时能自然看到新作品。
final recentCreationsProvider = FutureProvider.autoDispose<List<ImageTask>>((
  ref,
) async {
  final store = ref.watch(localCreationStoreProvider);
  return store.list(limit: 8);
});
