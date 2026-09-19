import 'dart:io' show Platform;

class AppConfig {
  const AppConfig._();

  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// Android 模拟器里 `localhost` 是模拟器自己,不是宿主机,必须用 10.0.2.2。
  /// 真机调试需要把这里改成局域网 IP 或者用 adb reverse。
  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (Platform.isAndroid) return 'http://10.0.2.2:8080/api/v1';
    return 'http://localhost:8080/api/v1';
  }
}
