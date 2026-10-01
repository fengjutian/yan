import 'package:ai_image_studio/features/assets/data/asset_repository.dart';
import 'package:ai_image_studio/features/assets/presentation/asset_upload_controller.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:ai_image_studio/features/ai_settings/presentation/ai_settings_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

@immutable
class StyleTransferState {
  const StyleTransferState({
    this.styleId,
    this.strength = 0.7, // 0..1
    this.protectFace = true,
    this.protectSkin = true,
    this.protectBackground = false,
    this.submitting = false,
    this.taskId,
    this.resultBytes,
    this.errorMessage,
  });

  final String? styleId;
  final double strength;
  final bool protectFace;
  final bool protectSkin;
  final bool protectBackground;
  final bool submitting;
  final String? taskId;
  final Uint8List? resultBytes;
  final String? errorMessage;

  StyleTransferState copyWith({
    String? styleId,
    double? strength,
    bool? protectFace,
    bool? protectSkin,
    bool? protectBackground,
    bool? submitting,
    String? taskId,
    Uint8List? resultBytes,
    String? errorMessage,
    bool clearError = false,
    bool clearTask = false,
  }) => StyleTransferState(
    styleId: styleId ?? this.styleId,
    strength: strength ?? this.strength,
    protectFace: protectFace ?? this.protectFace,
    protectSkin: protectSkin ?? this.protectSkin,
    protectBackground: protectBackground ?? this.protectBackground,
    submitting: submitting ?? this.submitting,
    taskId: clearTask ? null : (taskId ?? this.taskId),
    resultBytes: resultBytes ?? this.resultBytes,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

class StyleTransferController extends StateNotifier<StyleTransferState> {
  StyleTransferController(this._ref, this._assets, {required this.localOnly})
    : super(const StyleTransferState());

  final Ref _ref;
  final AssetRepository _assets;
  final bool localOnly;
  static const _uuid = Uuid();

  void setStyle(String id) =>
      state = state.copyWith(styleId: id, clearError: true);
  void setStrength(double v) => state = state.copyWith(strength: v);
  void setProtectFace(bool v) =>
      state = state.copyWith(protectFace: v, clearError: true);
  void setProtectSkin(bool v) =>
      state = state.copyWith(protectSkin: v, clearError: true);
  void setProtectBackground(bool v) =>
      state = state.copyWith(protectBackground: v, clearError: true);

  /// 上传源图并提交风格迁移任务。
  Future<String?> submit({
    required Uint8List sourceBytes,
    required String prompt,
    required String aspectRatio,
  }) async {
    if (state.styleId == null) {
      state = state.copyWith(errorMessage: '请先选择风格');
      return null;
    }
    if (state.submitting) return null;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      if (localOnly) {
        final styleName = switch (state.styleId) {
          'local-natural' => '自然人像',
          'local-film' => '柔和胶片',
          'local-cinematic' => '电影质感',
          'local-clean' => '清透日系',
          _ => state.styleId!,
        };
        final result = await _ref.read(localAIClientProvider).styleTransfer(
          sourceBytes: sourceBytes,
          prompt:
              '$prompt，应用$styleName风格，风格强度${(state.strength * 100).round()}%，'
              '${state.protectFace ? '保持人物五官，' : ''}'
              '${state.protectSkin ? '保持自然肤色与肤质，' : ''}'
              '${state.protectBackground ? '保持原有背景结构，' : ''}'
              '画面自然精细。',
          aspectRatio: aspectRatio,
        );
        state = state.copyWith(submitting: false, resultBytes: result);
        return null;
      }
      if (sourceBytes.length > maxUploadBytes) {
        throw StateError('图片不能超过 10 MB');
      }
      final source = await _assets.upload(
        XFile.fromData(
          sourceBytes,
          mimeType: 'image/jpeg',
          name: 'style-${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
        onProgress: (_) {},
      );
      final dio = _ref.read(apiClientProvider).dio;
      final response = await dio.post<Map<String, dynamic>>(
        '/image-tasks',
        options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
        data: {
          'type': 'STYLE_TRANSFER',
          'prompt': prompt,
          'source_asset_id': source.id,
          'style_id': state.styleId,
          'aspect_ratio': aspectRatio,
          'count': 1,
          'prompt_optimizer': true,
          'options': {
            'strength': state.strength,
            'protect_face': state.protectFace,
            'protect_skin': state.protectSkin,
            'protect_background': state.protectBackground,
          },
        },
      );
      final id = (response.data?['id'] as String?) ?? '';
      state = state.copyWith(submitting: false, taskId: id);
      return id;
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        errorMessage: _friendlyError(e),
      );
      return null;
    }
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message.toString();
    if (error is DioException) {
      final body = error.response?.data;
      if (body is Map) {
        final baseResponse = body['base_resp'];
        if (baseResponse is Map && baseResponse['status_msg'] != null) {
          return baseResponse['status_msg'].toString();
        }
      }
      if (error.response?.statusCode == 401) return 'API Key 无效，请检查 AI 设置';
      return '连接大模型失败，请检查网络和 AI 设置';
    }
    return '风格迁移失败，请稍后重试';
  }
}

final styleTransferControllerProvider =
    StateNotifierProvider.autoDispose<
      StyleTransferController,
      StyleTransferState
    >(
      (ref) => StyleTransferController(
        ref,
        ref.watch(assetRepositoryProvider),
        localOnly: ref.watch(
          aiSettingsControllerProvider.select(
            (state) => state.settings.preferLocal,
          ),
        ),
      ),
    );
