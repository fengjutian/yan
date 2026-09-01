import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/core/storage/token_storage.dart';
import 'package:ai_image_studio/features/auth/data/auth_models.dart';
import 'package:dio/dio.dart';

class AuthRepository {
  AuthRepository(
      {required ApiClient apiClient, required TokenStorage tokenStorage})
      : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  Future<AuthSession> login({required String email, required String password}) {
    return _authenticate('/auth/login', {
      'email': email,
      'password': password,
      'device_name': 'flutter',
    });
  }

  Future<AuthSession> register({
    required String email,
    required String password,
    required String nickname,
  }) {
    return _authenticate('/auth/register', {
      'email': email,
      'password': password,
      'nickname': nickname,
      'device_name': 'flutter',
    });
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    try {
      if (refreshToken != null) {
        await _apiClient.dio.post<void>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } finally {
      await _tokenStorage.clear();
    }
  }

  Future<AuthUser?> restoreSession() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>('/me');
      return AuthUser.fromJson(response.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _tokenStorage.clear();
        return null;
      }
      throw ApiException.fromDio(error);
    }
  }

  Future<AuthSession> _authenticate(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        path,
        data: payload,
      );
      final session = AuthSession.fromJson(response.data!);
      await _tokenStorage.write(
        accessToken: session.tokens.accessToken,
        refreshToken: session.tokens.refreshToken,
      );
      return session;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
