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

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
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
