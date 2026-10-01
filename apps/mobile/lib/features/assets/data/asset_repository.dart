import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/features/assets/data/asset_model.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

class AssetRepository {
  AssetRepository(this._apiClient, {this.localOnly = true});
  final ApiClient _apiClient;
  final bool localOnly;

  Future<ImageAsset> upload(XFile file,
      {required void Function(double) onProgress}) async {
    if (localOnly) {
      final bytes = await file.readAsBytes();
      onProgress(1);
      return ImageAsset(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        url: file.path,
        thumbnailUrl: file.path,
        mimeType: file.mimeType ?? 'image/jpeg',
        width: 0,
        height: 0,
        byteSize: bytes.length,
      );
    }
    try {
      final bytes = await file.readAsBytes();
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/assets',
        data: FormData.fromMap(
            {'file': MultipartFile.fromBytes(bytes, filename: file.name)}),
        onSendProgress: (sent, total) {
          if (total > 0) onProgress(sent / total);
        },
      );
      return ImageAsset.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> delete(String assetId) async {
    if (localOnly || assetId.startsWith('local-')) return;
    try {
      await _apiClient.dio.delete<void>('/assets/$assetId');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
