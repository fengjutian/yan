import 'package:ai_image_studio/core/config/app_config.dart';
import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({Dio? dio})
      : dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.apiBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
                headers: const {'Accept': 'application/json'},
              ),
            );

  final Dio dio;
}

