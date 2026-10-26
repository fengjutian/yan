import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:ai_image_studio/features/templates/data/template_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final templateRepositoryProvider = Provider<TemplateRepository>(
  (ref) => TemplateRepository(),
);

/// 全部模板(按分类缓存),启动时拉一次,后续只在 invalidate 后重拉。
final allTemplatesProvider = FutureProvider<List<InspirationTemplate>>((
  ref,
) async {
  final repo = ref.watch(templateRepositoryProvider);
  return repo.listByCategory();
});

final featuredTemplatesProvider = FutureProvider<List<InspirationTemplate>>((
  ref,
) async {
  final repo = ref.watch(templateRepositoryProvider);
  return repo.featured();
});

final templateByCategoryProvider = FutureProvider.family
    .autoDispose<List<InspirationTemplate>, TemplateCategory?>((
      ref,
      cat,
    ) async {
      final repo = ref.watch(templateRepositoryProvider);
      return repo.listByCategory(cat);
    });

final templateByIdProvider = FutureProvider.family
    .autoDispose<InspirationTemplate?, String>((ref, id) async {
      final repo = ref.watch(templateRepositoryProvider);
      return repo.findById(id);
    });

/// 模板收藏:本地持久化。登录后迁移到后端 /me/template-favorites。
///
/// SharedPreferences 的读取是异步的,但收藏状态需要同步参与构建。
/// 因此先以空集合启动,初始化完成后再更新状态,避免页面因 preferences
/// 尚未就绪而抛错。
class TemplateFavoritesService {
  TemplateFavoritesService(this._prefs);
  final Future<SharedPreferences> _prefs;
  static const _key = 'template_favorites';

  Future<Set<String>> read() async {
    final prefs = await _prefs;
    return (prefs.getStringList(_key) ?? const <String>[]).toSet();
  }

  Future<void> toggle(String id) async {
    final prefs = await _prefs;
    final current = (prefs.getStringList(_key) ?? const <String>[]).toSet();
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    await prefs.setStringList(_key, current.toList());
  }
}

final templateFavoritesServiceProvider = Provider<TemplateFavoritesService>(
  (ref) => TemplateFavoritesService(SharedPreferences.getInstance()),
);

final templateFavoritesProvider =
    StateNotifierProvider<TemplateFavoritesNotifier, Set<String>>((ref) {
      final svc = ref.watch(templateFavoritesServiceProvider);
      return TemplateFavoritesNotifier(svc);
    });

class TemplateFavoritesNotifier extends StateNotifier<Set<String>> {
  TemplateFavoritesNotifier(this._svc) : super(const {}) {
    _ready = _hydrate();
  }

  final TemplateFavoritesService _svc;
  late final Future<void> _ready;

  Future<void> _hydrate() async {
    try {
      final values = await _svc.read();
      if (mounted) state = values;
    } catch (_) {
      // 读取失败时保持空收藏,不阻塞模板浏览。
    }
  }

  Future<void> toggle(String id) async {
    await _ready;
    try {
      await _svc.toggle(id);
      final values = await _svc.read();
      if (mounted) state = values;
    } catch (_) {
      // 写入失败时不改变当前状态,下次启动仍以磁盘数据为准。
    }
  }

  bool contains(String id) => state.contains(id);
}
