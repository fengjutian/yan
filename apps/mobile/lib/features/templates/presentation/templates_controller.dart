import 'package:ai_image_studio/features/share/presentation/share_controller.dart';
import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:ai_image_studio/features/templates/data/template_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final templateRepositoryProvider = Provider<TemplateRepository>(
  (ref) => TemplateRepository(),
);

/// 全部模板(按分类缓存),启动时拉一次,后续只在 invalidate 后重拉。
final allTemplatesProvider =
    FutureProvider<List<InspirationTemplate>>((ref) async {
  final repo = ref.watch(templateRepositoryProvider);
  return repo.listByCategory();
});

final featuredTemplatesProvider =
    FutureProvider<List<InspirationTemplate>>((ref) async {
  final repo = ref.watch(templateRepositoryProvider);
  return repo.featured();
});

final templateByCategoryProvider = FutureProvider.family
    .autoDispose<List<InspirationTemplate>, TemplateCategory?>((ref, cat) async {
  final repo = ref.watch(templateRepositoryProvider);
  return repo.listByCategory(cat);
});

final templateByIdProvider =
    FutureProvider.family.autoDispose<InspirationTemplate?, String>(
        (ref, id) async {
  final repo = ref.watch(templateRepositoryProvider);
  return repo.findById(id);
});

/// 模板收藏:本地持久化。登录后迁移到后端 /me/template-favorites。
class TemplateFavoritesService {
  TemplateFavoritesService(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'template_favorites';

  Set<String> read() =>
      (_prefs.getStringList(_key) ?? const <String>[]).toSet();

  Future<void> toggle(String id) async {
    final cur = read();
    if (cur.contains(id)) {
      cur.remove(id);
    } else {
      cur.add(id);
    }
    await _prefs.setStringList(_key, cur.toList());
  }
}

final templateFavoritesServiceProvider =
    Provider<TemplateFavoritesService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (v) => v,
        orElse: () =>
            throw StateError('sharedPreferencesProvider 未就绪'),
      );
  return TemplateFavoritesService(prefs);
});

final templateFavoritesProvider =
    StateNotifierProvider<TemplateFavoritesNotifier, Set<String>>((ref) {
  final svc = ref.watch(templateFavoritesServiceProvider);
  return TemplateFavoritesNotifier(svc);
});

class TemplateFavoritesNotifier extends StateNotifier<Set<String>> {
  TemplateFavoritesNotifier(this._svc) : super(_svc.read());
  final TemplateFavoritesService _svc;

  Future<void> toggle(String id) async {
    await _svc.toggle(id);
    state = _svc.read();
  }

  bool contains(String id) => state.contains(id);
}