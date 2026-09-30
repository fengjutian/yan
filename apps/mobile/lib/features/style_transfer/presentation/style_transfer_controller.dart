import 'dart:typed_data';

import 'package:ai_image_studio/features/assets/data/asset_repository.dart';
import 'package:ai_image_studio/features/assets/presentation/asset_upload_controller.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
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
    this.errorMessage,
  });

  final String? styleId;
  final double strength;
  final bool protectFace;
  final bool protectSkin;
  final bool protectBackground;
  final bool submitting;
  final String? taskId;
  final String? errorMessage;

  StyleTransferState copyWith({
    String? styleId,
    double? strength,
    bool? protectFace,
    bool? protectSkin,
    bool? protectBackground,
    bool? submitting,
    String? taskId,
    String? errorMessage,
    bool clearError = false,
    bool clearTask = false,
  }) =>
      StyleTransferState(
        styleId: styleId ?? this.styleId,
        strength: strength ?? this.strength,
        protectFace: protectFace ?? this.protectFace,
        protectSkin: protectSkin ?? this.protectSkin,
        protectBackground: protectBackground ?? this.protectBackground,
        submitting: submitting ?? this.submitting,
        taskId: clearTask ? null : (taskId ?? this.taskId),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class StyleTransferController extends StateNotifier<StyleTransferState> {
  StyleTransferController(this._ref, this._assets)
      : super(const StyleTransferState());

  final Ref _ref;
  final AssetRepository _assets;
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

  /// 提交风格迁移任务。
  /// 后端 STYLE_TRANSFER 接口尚未上线,这里先 fallback 到 CHARACTER_REFERENCE,
  /// 把 strength / protect 写入任务 options,后端真实接口可用后切换。
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
      if (sourceBytes.length > maxUploadBytes) {
        throw StateError('图片不能超过 10 MB');
      }
      final source = await _assets.upload(
        XFile.fromData(sourceBytes,
            mimeType: 'image/jpeg',
            name: 'style-${DateTime.now().millisecondsSinceEpoch}.jpg'),
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
      state = state.copyWith(submitting: false, errorMessage: e.toString());
      return null;
    }
  }
}

final styleTransferControllerProvider = StateNotifierProvider.autoDispose<
        StyleTransferController, StyleTransferState>(
    (ref) => StyleTransferController(
          ref,
          ref.watch(assetRepositoryProvider),
        ));
