import 'dart:typed_data';
import 'package:ai_image_studio/features/assets/data/asset_model.dart';
import 'package:ai_image_studio/features/assets/data/asset_repository.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

const maxUploadBytes = 10 * 1024 * 1024;
final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());
final assetRepositoryProvider = Provider<AssetRepository>(
    (ref) => AssetRepository(ref.watch(apiClientProvider)));
final assetUploadControllerProvider =
    StateNotifierProvider.autoDispose<AssetUploadController, AssetUploadState>(
  (ref) => AssetUploadController(
      ref.watch(assetRepositoryProvider), ref.watch(imagePickerProvider)),
);

class AssetUploadState {
  const AssetUploadState(
      {this.selectedFile,
      this.previewBytes,
      this.uploadedAsset,
      this.uploading = false,
      this.progress = 0,
      this.errorMessage});
  final XFile? selectedFile;
  final Uint8List? previewBytes;
  final ImageAsset? uploadedAsset;
  final bool uploading;
  final double progress;
  final String? errorMessage;
}

class AssetUploadController extends StateNotifier<AssetUploadState> {
  AssetUploadController(this._repository, this._picker)
      : super(const AssetUploadState());
  final AssetRepository _repository;
  final ImagePicker _picker;

  Future<void> selectImage() async {
    final selected = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95);
    if (selected == null) return;
    final bytes = await selected.readAsBytes();
    if (bytes.length > maxUploadBytes) {
      state = const AssetUploadState(errorMessage: '图片不能超过 10 MB');
      return;
    }
    state = AssetUploadState(selectedFile: selected, previewBytes: bytes);
  }

  Future<bool> upload() async {
    final file = state.selectedFile;
    if (file == null) {
      state = const AssetUploadState(errorMessage: '请先选择图片');
      return false;
    }
    final preview = state.previewBytes;
    state = AssetUploadState(
        selectedFile: file, previewBytes: preview, uploading: true);
    try {
      final asset = await _repository.upload(file, onProgress: (progress) {
        state = AssetUploadState(
            selectedFile: file,
            previewBytes: preview,
            uploading: true,
            progress: progress);
      });
      state = AssetUploadState(
          selectedFile: file,
          previewBytes: preview,
          uploadedAsset: asset,
          progress: 1);
      return true;
    } catch (error) {
      state = AssetUploadState(
          selectedFile: file,
          previewBytes: preview,
          errorMessage: error.toString());
      return false;
    }
  }
}
