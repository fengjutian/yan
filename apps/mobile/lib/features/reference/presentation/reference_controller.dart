import 'dart:async';
import 'dart:typed_data';

import 'package:ai_image_studio/features/assets/data/asset_model.dart';
import 'package:ai_image_studio/features/assets/data/asset_repository.dart';
import 'package:ai_image_studio/features/assets/presentation/asset_upload_controller.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:ai_image_studio/features/generate/data/generate_repository.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_controller.dart';
import 'package:ai_image_studio/features/styles/data/style_model.dart';
import 'package:ai_image_studio/features/styles/data/style_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

final styleRepositoryProvider = Provider<StyleRepository>(
    (ref) => StyleRepository(ref.watch(apiClientProvider)));
final referenceControllerProvider =
    StateNotifierProvider.autoDispose<ReferenceController, ReferenceState>(
        (ref) => ReferenceController(
              ref.watch(assetRepositoryProvider),
              ref.watch(generateRepositoryProvider),
              ref.watch(styleRepositoryProvider),
              ref.watch(imagePickerProvider),
            ));

class ReferenceState {
  const ReferenceState({
    this.previewBytes,
    this.sourceAsset,
    this.styles = const [],
    this.styleId,
    this.prompt = '',
    this.aspectRatio = '1:1',
    this.busy = false,
    this.uploadProgress = 0,
    this.task,
    this.errorMessage,
  });
  final Uint8List? previewBytes;
  final ImageAsset? sourceAsset;
  final List<StylePreset> styles;
  final String? styleId;
  final String prompt;
  final String aspectRatio;
  final bool busy;
  final double uploadProgress;
  final ImageTask? task;
  final String? errorMessage;

  ReferenceState copyWith({
    Uint8List? previewBytes,
    ImageAsset? sourceAsset,
    List<StylePreset>? styles,
    String? styleId,
    String? prompt,
    String? aspectRatio,
    bool? busy,
    double? uploadProgress,
    ImageTask? task,
    String? errorMessage,
    bool clearError = false,
  }) =>
      ReferenceState(
        previewBytes: previewBytes ?? this.previewBytes,
        sourceAsset: sourceAsset ?? this.sourceAsset,
        styles: styles ?? this.styles,
        styleId: styleId ?? this.styleId,
        prompt: prompt ?? this.prompt,
        aspectRatio: aspectRatio ?? this.aspectRatio,
        busy: busy ?? this.busy,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        task: task ?? this.task,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      );
}

class ReferenceController extends StateNotifier<ReferenceState> {
  ReferenceController(this._assets, this._generate, this._styles, this._picker)
      : super(const ReferenceState());
  final AssetRepository _assets;
  final GenerateRepository _generate;
  final StyleRepository _styles;
  final ImagePicker _picker;
  Timer? _timer;

  Future<void> loadStyles() async {
    if (state.styles.isNotEmpty) return;
    try {
      final styles = await _styles.list();
      state = state.copyWith(
          styles: styles,
          styleId: styles.isEmpty ? null : styles.first.id,
          clearError: true);
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
    }
  }

  Future<void> selectAndUpload() async {
    final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > maxUploadBytes) {
      state = state.copyWith(errorMessage: '图片不能超过 10 MB');
      return;
    }
    state = state.copyWith(
        previewBytes: bytes, busy: true, uploadProgress: 0, clearError: true);
    try {
      final asset = await _assets.upload(file, onProgress: (progress) {
        state = state.copyWith(
            previewBytes: bytes, busy: true, uploadProgress: progress);
      });
      state = state.copyWith(
          previewBytes: bytes,
          sourceAsset: asset,
          busy: false,
          uploadProgress: 1);
    } catch (error) {
      state = state.copyWith(
          previewBytes: bytes, busy: false, errorMessage: error.toString());
    }
  }

  void setStyle(String styleId) => state = state.copyWith(styleId: styleId);
  void setPrompt(String prompt) =>
      state = state.copyWith(prompt: prompt, clearError: true);
  void setAspectRatio(String ratio) =>
      state = state.copyWith(aspectRatio: ratio);

  Future<void> generate() async {
    if (state.sourceAsset == null ||
        state.styleId == null ||
        state.prompt.trim().isEmpty) {
      state = state.copyWith(errorMessage: '请上传参考图、选择风格并输入描述');
      return;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final task = await _generate.createCharacterReference(
        prompt: state.prompt.trim(),
        sourceAssetId: state.sourceAsset!.id,
        styleId: state.styleId!,
        aspectRatio: state.aspectRatio,
      );
      state = state.copyWith(busy: false, task: task);
      _schedule(task.id);
    } catch (error) {
      state = state.copyWith(busy: false, errorMessage: error.toString());
    }
  }

  void _schedule(String taskId) {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () => _poll(taskId));
  }

  Future<void> _poll(String taskId) async {
    try {
      final task = await _generate.get(taskId);
      state = state.copyWith(task: task, clearError: true);
      if (!task.isTerminal) _schedule(taskId);
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      _schedule(taskId);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
