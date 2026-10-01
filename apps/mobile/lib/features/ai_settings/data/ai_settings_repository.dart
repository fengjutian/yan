import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AIProvider {
  deepSeek,
  miniMax;

  String get storageValue => this == deepSeek ? 'deepseek' : 'minimax';
  String get label => this == deepSeek ? 'DeepSeek' : 'MiniMax';
  String get defaultBaseUrl => this == deepSeek
      ? 'https://api.deepseek.com'
      : 'https://api.minimaxi.com';
  String get defaultModel =>
      this == deepSeek ? 'deepseek-v4-pro' : 'MiniMax-M3';

  static AIProvider fromStorage(String? value) =>
      value == 'deepseek' ? deepSeek : miniMax;
}

class AISettings {
  const AISettings({
    this.enabled = false,
    this.preferLocal = true,
    this.provider = AIProvider.miniMax,
    this.baseUrl = 'https://api.minimaxi.com',
    this.model = 'MiniMax-M3',
    this.apiKey = '',
  });

  final bool enabled;
  final bool preferLocal;
  final AIProvider provider;
  final String baseUrl;
  final String model;
  final String apiKey;

  bool get canCallLocally =>
      enabled && preferLocal && apiKey.trim().isNotEmpty;

  AISettings copyWith({
    bool? enabled,
    bool? preferLocal,
    AIProvider? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) =>
      AISettings(
        enabled: enabled ?? this.enabled,
        preferLocal: preferLocal ?? this.preferLocal,
        provider: provider ?? this.provider,
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

  // 保留旧 key 名称，MiniMax 用户升级后无需重新配置。
  static const _enabledKey = 'ai.minimax.enabled';
  static const _preferLocalKey = 'ai.minimax.prefer_local';
  static const _providerKey = 'ai.provider';
  static const _baseUrlKey = 'ai.minimax.base_url';
  static const _modelKey = 'ai.minimax.model';
  static const _apiKeyKey = 'ai.minimax.api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<AISettings> load() async {
    final provider = AIProvider.fromStorage(
      await _storage.read(key: _providerKey),
    );
    return AISettings(
      enabled: await _storage.read(key: _enabledKey) == 'true',
      preferLocal:
          (await _storage.read(key: _preferLocalKey) ?? 'true') == 'true',
      provider: provider,
      baseUrl: await _storage.read(key: _baseUrlKey) ?? provider.defaultBaseUrl,
      model: await _storage.read(key: _modelKey) ?? provider.defaultModel,
      apiKey: await _storage.read(key: _apiKeyKey) ?? '',
    );
  }

  @override
  Future<void> save(AISettings settings) async {
    await Future.wait([
      _storage.write(key: _enabledKey, value: settings.enabled.toString()),
      _storage.write(
        key: _preferLocalKey,
        value: settings.preferLocal.toString(),
      ),
      _storage.write(key: _providerKey, value: settings.provider.storageValue),
      _storage.write(key: _baseUrlKey, value: settings.baseUrl.trim()),
      _storage.write(key: _modelKey, value: settings.model.trim()),
      _storage.write(key: _apiKeyKey, value: settings.apiKey.trim()),
    ]);
  }
}
