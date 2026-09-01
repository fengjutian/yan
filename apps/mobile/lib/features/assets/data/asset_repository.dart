import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/features/assets/data/asset_model.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

class AssetRepository {
  AssetRepository(this._apiClient);
  final ApiClient _apiClient;

  Future<ImageAsset> upload(XFile file,
      {required void Function(double) onProgress}) async {
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
    try {
      await _apiClient.dio.delete<void>('/assets/$assetId');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
