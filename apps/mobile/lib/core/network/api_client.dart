import 'package:ai_image_studio/core/config/app_config.dart';
import 'package:ai_image_studio/core/storage/token_storage.dart';
import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({required TokenStorage tokenStorage, Dio? dio})
      : dio = dio ?? Dio(_options()) {
    this.dio.interceptors.add(
          _AuthInterceptor(
            dio: this.dio,
            refreshDio: Dio(_options()),
            tokenStorage: tokenStorage,
          ),
        );
  }

  final Dio dio;

  static BaseOptions _options() => BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'Accept': 'application/json'},
      );
}

class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor({
    required this.dio,
    required this.refreshDio,
    required this.tokenStorage,
  });

  final Dio dio;
  final Dio refreshDio;
  final TokenStorage tokenStorage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isPublicAuthPath(options.path)) {
      final token = await tokenStorage.readAccessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        request.extra['auth_retried'] == true ||
        _isPublicAuthPath(request.path)) {
      handler.next(error);
      return;
    }

    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      await tokenStorage.clear();
      handler.next(error);
      return;
    }

    try {
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken, 'device_name': 'flutter'},
      );
      final body = response.data!;
      final accessToken = body['access_token'] as String;
      final replacementRefreshToken = body['refresh_token'] as String;
      await tokenStorage.write(
        accessToken: accessToken,
        refreshToken: replacementRefreshToken,
      );

      request.extra['auth_retried'] = true;
      request.headers['Authorization'] = 'Bearer $accessToken';
      handler.resolve(await dio.fetch<dynamic>(request));
    } on DioException {
      await tokenStorage.clear();
      handler.next(error);
    }
  }

  bool _isPublicAuthPath(String path) =>
      path.endsWith('/auth/login') ||
      path.endsWith('/auth/register') ||
      path.endsWith('/auth/refresh');
}
