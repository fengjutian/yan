import 'package:ai_image_studio/features/ai_settings/data/ai_settings_repository.dart';
import 'package:dio/dio.dart';

class LocalAIClient {
  LocalAIClient(this._settings, this._backend, {Dio? directClient})
      : _direct = directClient ?? Dio();

  static const promptSystemMessage =
      '你是专业的AI绘画提示词编辑。依据用户原意补充主体细节、环境、光线、构图、色彩和材质。'
      '不要改变主体，不要解释，不要使用标题或Markdown，只输出一段可直接用于图片生成的中文提示词，控制在80到220字。';

  final AISettingsStore _settings;
  final Dio _backend;
  final Dio _direct;

  /// 已启用本地配置时优先由 APP 直连 MiniMax；直连失败时回退现有后端。
  Future<String> complete(
    String prompt, {
    String systemMessage = promptSystemMessage,
  }) async {
    final settings = await _settings.load();
    if (settings.canCallLocally) {
      try {
        return await _callMiniMax(settings, prompt, systemMessage);
      } on DioException {
        // 国内线路偶发不可用时保留服务端降级能力。
      } on FormatException {
        // 上游响应不完整时同样回退。
      }
    }
    final response = await _backend.post<Map<String, dynamic>>(
      '/prompts/enhance',
      data: {'prompt': prompt},
    );
    final result = response.data?['prompt'];
    if (result is! String || result.trim().isEmpty) {
      throw const FormatException('AI 返回内容为空');
    }
    return result.trim();
  }

  Future<String> test(AISettings settings) => _callMiniMax(
        settings,
        '一只在窗边晒太阳的猫',
        '请简短优化用户的图片生成提示词，只返回优化结果。',
      );

  Future<String> _callMiniMax(
    AISettings settings,
    String prompt,
    String systemMessage,
  ) async {
    final response = await _direct.post<Map<String, dynamic>>(
      '${settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/v1/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${settings.apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
      data: {
        'model': settings.model.trim(),
        'messages': [
          {'role': 'system', 'content': systemMessage},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
        'max_completion_tokens': 500,
      },
    );
    final choices = response.data?['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('MiniMax 返回格式无效');
    }
    final message = choices.first['message'];
    var content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('MiniMax 返回内容为空');
    }
    content = content.trim();
    final thinkEnd = content.lastIndexOf('</think>');
    return thinkEnd >= 0
        ? content.substring(thinkEnd + '</think>'.length).trim()
        : content;
  }
}
