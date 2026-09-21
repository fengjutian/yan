import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AISettings {
  const AISettings({
    this.enabled = false,
    this.preferLocal = true,
    this.baseUrl = 'https://api.minimaxi.com',
    this.model = 'MiniMax-M2.5',
    this.apiKey = '',
  });

  final bool enabled;
  final bool preferLocal;
  final String baseUrl;
  final String model;
  final String apiKey;

  bool get canCallLocally => enabled && preferLocal && apiKey.trim().isNotEmpty;

  AISettings copyWith({
    bool? enabled,
    bool? preferLocal,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) =>
      AISettings(
        enabled: enabled ?? this.enabled,
        preferLocal: preferLocal ?? this.preferLocal,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
      );
}

abstract interface class AISettingsStore {
  Future<AISettings> load();
  Future<void> save(AISettings settings);
}

class SecureAISettingsRepository implements AISettingsStore {
  SecureAISettingsRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _enabledKey = 'ai.minimax.enabled';
  static const _preferLocalKey = 'ai.minimax.prefer_local';
  static const _baseUrlKey = 'ai.minimax.base_url';
  static const _modelKey = 'ai.minimax.model';
  static const _apiKeyKey = 'ai.minimax.api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<AISettings> load() async => AISettings(
        enabled: await _storage.read(key: _enabledKey) == 'true',
        preferLocal:
            (await _storage.read(key: _preferLocalKey) ?? 'true') == 'true',
        baseUrl:
            await _storage.read(key: _baseUrlKey) ?? 'https://api.minimaxi.com',
        model: await _storage.read(key: _modelKey) ?? 'MiniMax-M2.5',
        apiKey: await _storage.read(key: _apiKeyKey) ?? '',
      );

  @override
  Future<void> save(AISettings settings) async {
    await Future.wait([
      _storage.write(key: _enabledKey, value: settings.enabled.toString()),
      _storage.write(
          key: _preferLocalKey, value: settings.preferLocal.toString()),
      _storage.write(key: _baseUrlKey, value: settings.baseUrl.trim()),
      _storage.write(key: _modelKey, value: settings.model.trim()),
      _storage.write(key: _apiKeyKey, value: settings.apiKey.trim()),
    ]);
  }
}
