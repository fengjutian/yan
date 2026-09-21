import 'package:ai_image_studio/features/ai_settings/data/ai_settings_repository.dart';
import 'package:ai_image_studio/features/ai_settings/data/local_ai_client.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final aiSettingsStoreProvider = Provider<AISettingsStore>(
  (ref) => SecureAISettingsRepository(),
);

final localAIClientProvider = Provider<LocalAIClient>(
  (ref) => LocalAIClient(
    ref.watch(aiSettingsStoreProvider),
    ref.watch(apiClientProvider).dio,
  ),
);

final aiSettingsControllerProvider = StateNotifierProvider.autoDispose<
    AISettingsController, AISettingsState>(
  (ref) => AISettingsController(
    ref.watch(aiSettingsStoreProvider),
    ref.watch(localAIClientProvider),
  )..load(),
);

class AISettingsState {
  const AISettingsState({
    this.settings = const AISettings(),
    this.loading = true,
    this.saving = false,
    this.testing = false,
    this.message,
    this.isError = false,
  });

  final AISettings settings;
  final bool loading;
  final bool saving;
  final bool testing;
  final String? message;
  final bool isError;

  AISettingsState copyWith({
    AISettings? settings,
    bool? loading,
    bool? saving,
    bool? testing,
    String? message,
    bool? isError,
    bool clearMessage = false,
  }) =>
      AISettingsState(
        settings: settings ?? this.settings,
        loading: loading ?? this.loading,
        saving: saving ?? this.saving,
        testing: testing ?? this.testing,
        message: clearMessage ? null : message ?? this.message,
        isError: isError ?? this.isError,
      );
}

class AISettingsController extends StateNotifier<AISettingsState> {
  AISettingsController(this._store, this._client)
      : super(const AISettingsState());

  final AISettingsStore _store;
  final LocalAIClient _client;

  Future<void> load() async {
    try {
      state = AISettingsState(settings: await _store.load(), loading: false);
    } catch (error) {
      state = AISettingsState(
          loading: false, message: error.toString(), isError: true);
    }
  }

  void update(AISettings value) =>
      state = state.copyWith(settings: value, clearMessage: true);

  Future<bool> save() async {
    final value = state.settings;
    if (value.enabled &&
        (value.apiKey.trim().isEmpty ||
            value.baseUrl.trim().isEmpty ||
            value.model.trim().isEmpty)) {
      state = state.copyWith(message: '请填写 API Key、接口地址和模型名称', isError: true);
      return false;
    }
    state = state.copyWith(saving: true, clearMessage: true);
    try {
      await _store.save(value);
      state = state.copyWith(saving: false, message: '设置已安全保存', isError: false);
      return true;
    } catch (error) {
      state = state.copyWith(
          saving: false, message: error.toString(), isError: true);
      return false;
    }
  }

  Future<void> test() async {
    final value = state.settings;
    if (value.apiKey.trim().isEmpty) {
      state = state.copyWith(message: '请先填写 API Key', isError: true);
      return;
    }
    state = state.copyWith(testing: true, clearMessage: true);
    try {
      await _client.test(value);
      state = state.copyWith(
          testing: false, message: 'MiniMax 国内线路连接成功', isError: false);
    } catch (error) {
      state = state.copyWith(
          testing: false, message: '连接失败：$error', isError: true);
    }
  }
}
