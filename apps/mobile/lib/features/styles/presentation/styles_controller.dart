import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:ai_image_studio/features/ai_settings/presentation/ai_settings_controller.dart';
import 'package:ai_image_studio/features/styles/data/style_model.dart';
import 'package:ai_image_studio/features/styles/data/style_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final styleRepositoryProvider = Provider<StyleRepository>((ref) {
  final localOnly = ref.watch(aiSettingsControllerProvider
      .select((state) => state.settings.preferLocal));
  return StyleRepository(ref.watch(apiClientProvider), localOnly: localOnly);
});

/// 风格列表:FutureProvider,超时 60s 自动 invalidate。
final stylesProvider = FutureProvider<List<StylePreset>>((ref) async {
  final repo = ref.watch(styleRepositoryProvider);
  return repo.list();
});
