import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次使用 AI 生成前的年龄与内容合规确认。
///
/// 只在本机保存一次；不涉及账号，也不上传确认结果。
class AiConsent {
  const AiConsent._();

  static const _key = 'compliance.ai_consent.v1';

  static Future<bool> ensure(BuildContext context) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_key) == true) return true;
    if (!context.mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('使用 AI 生成前请确认'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. 本 App 的 AI 能力由第三方服务商提供，输出可能不准确、不完整或不符合预期。'),
              SizedBox(height: 8),
              Text('2. 禁止生成违法、侵权、色情、暴力、仇恨、未成年人相关或违反服务商政策的内容。'),
              SizedBox(height: 8),
              Text('3. AI 生成内容会带有“AI 生成”标识，分享/导出水印不可关闭。'),
              SizedBox(height: 8),
              Text('4. 你需要自行承担使用 AI 生成内容产生的责任，并遵守所在地区法律法规。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('我已满 18 岁并同意'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    await preferences.setBool(_key, true);
    return true;
  }
}
