import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动的《用户协议》《隐私政策》确认。
///
/// 小米应用商店（以及工信部 164 号文）要求：用户同意前不得收集设备信息、
/// 不得申请权限、不得发起网络请求。因此这个确认必须在进入首页之前完成，
/// 拒绝时直接退出，不做任何数据读写。
class PrivacyConsent {
  const PrivacyConsent._();

  /// 政策文本有实质变更时改版本号，老用户会重新确认。
  static const _version = 'v1';
  static const _key = 'compliance.privacy_consent.$_version';

  static Future<bool> isAccepted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) == true;
  }

  static Future<void> accept() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, true);
  }

  /// 用户拒绝：只退出进程，不写入任何数据。
  static void declineAndExit() {
    SystemNavigator.pop();
  }
}
