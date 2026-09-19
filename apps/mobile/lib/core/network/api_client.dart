import 'package:ai_image_studio/core/config/app_config.dart';
import 'package:ai_image_studio/core/storage/token_storage.dart';
import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    Dio? dio,
    this.onSessionInvalidated,
  }) : dio = dio ?? Dio(_options()) {
    this.dio.interceptors.add(
          _AuthInterceptor(
            dio: this.dio,
            refreshDio: Dio(_options()),
            tokenStorage: tokenStorage,
            onSessionInvalidated: onSessionInvalidated,
          ),
        );
  }

  final Dio dio;

  /// Refresh token 失效后回调,用于通知 UI 跳回登录页。
  final void Function()? onSessionInvalidated;

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
    this.onSessionInvalidated,
  });

  final Dio dio;
  final Dio refreshDio;
  final TokenStorage tokenStorage;
  final void Function()? onSessionInvalidated;

  /// 把多个并发 401 合并成同一次 /auth/refresh,避免 refresh_token 被快速消耗。
  Future<void>? _refreshing;

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

    // 已重试过的请求依然 401(例如新拿到的 access token 也无效),直接放行错误。
    // 避免无限递归到 refresh。
    if (request.extra['auth_double_retried'] == true) {
      await tokenStorage.clear();
      onSessionInvalidated?.call();
      handler.next(error);
      return;
    }

    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      await tokenStorage.clear();
      onSessionInvalidated?.call();
      handler.next(error);
      return;
    }

    try {
      // 所有等待中的 401 共享同一个 refresh future。
      _refreshing ??= _doRefresh(refreshToken);
      final newAccess = await _refreshing!;
      _refreshing = null;
      if (newAccess == null) {
        await tokenStorage.clear();
        onSessionInvalidated?.call();
        handler.next(error);
        return;
      }

      request.extra['auth_retried'] = true;
      request.headers['Authorization'] = 'Bearer $newAccess';
      try {
        final retried = await dio.fetch<dynamic>(request);
        handler.resolve(retried);
      } on DioException catch (e) {
        // 重试还是 401,标记 double_retried,下一次直接放过。
        if (e.response?.statusCode == 401) {
          request.extra['auth_double_retried'] = true;
        }
        handler.next(e);
      }
    } catch (_) {
      _refreshing = null;
      await tokenStorage.clear();
      onSessionInvalidated?.call();
      handler.next(error);
    }
  }

  /// 返回新 access token;失败/返回 null 都视为 refresh 失效。
  Future<String?> _doRefresh(String refreshToken) async {
    try {
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken, 'device_name': 'flutter'},
      );
      final body = response.data;
      if (body == null) return null;
      final access = body['access_token'];
      final nextRefresh = body['refresh_token'];
      if (access is! String || nextRefresh is! String) return null;
      await tokenStorage.write(
        accessToken: access,
        refreshToken: nextRefresh,
      );
      return access;
    } on DioException {
      return null;
    }
  }

  bool _isPublicAuthPath(String path) =>
      path.endsWith('/auth/login') ||
      path.endsWith('/auth/register') ||
      path.endsWith('/auth/refresh');
}
