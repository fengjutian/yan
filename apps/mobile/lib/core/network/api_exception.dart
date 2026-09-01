import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({required this.code, required this.message});

  final String code;
  final String message;

  factory ApiException.fromDio(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final value = body['error'];
      if (value is Map<String, dynamic>) {
        return ApiException(
          code: value['code'] as String? ?? 'UNKNOWN_ERROR',
          message: value['message'] as String? ?? '请求失败，请稍后重试',
        );
      }
    }
    return const ApiException(
      code: 'NETWORK_ERROR',
      message: '无法连接服务器，请检查网络后重试',
    );
  }

  @override
  String toString() => message;
}

