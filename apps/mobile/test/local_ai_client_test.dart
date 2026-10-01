import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_image_studio/features/ai_settings/data/ai_settings_repository.dart';
import 'package:ai_image_studio/features/ai_settings/data/local_ai_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('优先使用 APP 本地 MiniMax 配置', () async {
    final direct = Dio()..httpClientAdapter = _JsonAdapter('本地结果');
    final backend = Dio()..httpClientAdapter = _JsonAdapter('后端结果');
    final client = LocalAIClient(
      _MemorySettings(const AISettings(
        enabled: true,
        preferLocal: true,
        apiKey: 'secret',
      )),
      backend,
      directClient: direct,
    );

    expect(await client.complete('测试'), '本地结果');
  });

  test('本地 AI 未启用时使用服务端', () async {
    final directAdapter = _JsonAdapter('不应调用');
    final direct = Dio()..httpClientAdapter = directAdapter;
    final backend = Dio()..httpClientAdapter = _JsonAdapter('后端结果');
    final client = LocalAIClient(
      _MemorySettings(const AISettings(apiKey: 'secret')),
      backend,
      directClient: direct,
    );

    expect(await client.complete('测试'), '后端结果');
    expect(directAdapter.calls, 0);
  });

  test('DeepSeek 使用国内官方地址和最新模型', () async {
    final adapter = _JsonAdapter('DeepSeek 结果');
    final direct = Dio()..httpClientAdapter = adapter;
    final client = LocalAIClient(
      _MemorySettings(const AISettings(
        enabled: true,
        preferLocal: true,
        provider: AIProvider.deepSeek,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-pro',
        apiKey: 'secret',
      )),
      Dio(),
      directClient: direct,
    );

    expect(await client.complete('测试'), 'DeepSeek 结果');
    expect(adapter.lastPath, 'https://api.deepseek.com/chat/completions');
    expect(adapter.lastData?['model'], 'deepseek-v4-pro');
  });

  test('MiniMax 使用国内官方地址和最新模型', () async {
    final adapter = _JsonAdapter('MiniMax 结果');
    final direct = Dio()..httpClientAdapter = adapter;
    final client = LocalAIClient(
      _MemorySettings(const AISettings(
        enabled: true,
        preferLocal: true,
        apiKey: 'secret',
      )),
      Dio(),
      directClient: direct,
    );

    expect(await client.complete('测试'), 'MiniMax 结果');
    expect(adapter.lastPath, 'https://api.minimaxi.com/v1/chat/completions');
    expect(adapter.lastData?['model'], 'MiniMax-M3');
  });
}

class _MemorySettings implements AISettingsStore {
  _MemorySettings(this.value);
  AISettings value;

  @override
  Future<AISettings> load() async => value;

  @override
  Future<void> save(AISettings settings) async => value = settings;
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.content);
  final String content;
  int calls = 0;
  String? lastPath;
  Map<String, dynamic>? lastData;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    lastPath = options.uri.toString();
    lastData = options.data as Map<String, dynamic>?;
    final isBackend = options.path.endsWith('/prompts/enhance');
    final body = isBackend
        ? {'prompt': content}
        : {
            'choices': [
              {
                'message': {'content': content}
              }
            ]
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
