import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kReleaseMode;

class AppConfig {
  const AppConfig._();

  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// 上架构建可通过 --dart-define=SUPPORT_EMAIL=... 配置反馈/举报邮箱。
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

  /// 上架构建可通过 --dart-define=APP_VERSION=1.0.0 传入版本号用于“关于”展示。
  static const appVersion = String.fromEnvironment('APP_VERSION');

  /// 开发者主体名称，商店资料需与本值一致（--dart-define=DEVELOPER_NAME=...）。
  static const developerName = String.fromEnvironment('DEVELOPER_NAME');

  /// 工信部 App 备案号（--dart-define=APP_BEIAN=京ICP备xxxxxxxx号-xA）。
  /// 备案完成后必须注入：应用商店要求 App 内可查阅备案信息。
  static const beianNumber = String.fromEnvironment('APP_BEIAN');

  /// 在线《隐私政策》与《用户协议》地址，商店后台和 App 内都需要可访问链接。
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const termsUrl = String.fromEnvironment('TERMS_URL');

  /// 是否启用开发者后端。v1 是本地优先的独立客户端：release 默认关闭后端，
  /// 只在显式传 --dart-define=ENABLE_BACKEND=true 时才连接 API。
  static const _enableBackend = bool.fromEnvironment('ENABLE_BACKEND');
  static bool get backendEnabled => _enableBackend || !kReleaseMode;

  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Android 模拟器里 `localhost` 是模拟器自己,不是宿主机,必须用 10.0.2.2。
  /// 真机调试需要把这里改成局域网 IP 或者用 adb reverse。
  /// release 未注入 API_BASE_URL 时返回空串：调用方应跳过网络请求。
  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
    if (kReleaseMode) return '';
    if (Platform.isAndroid) return 'http://10.0.2.2:8080/api/v1';
    return 'http://localhost:8080/api/v1';
  }
}
