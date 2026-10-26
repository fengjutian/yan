import 'package:ai_image_studio/core/config/app_config.dart';
import 'package:flutter/material.dart';

/// v1 独立客户端的隐私、协议与 AI 内容说明。
/// 商店上架时仍需在 App Store Connect / Google Play 提供对应的在线隐私政策 URL。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final supportEmail = AppConfig.supportEmail.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('隐私与协议')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const _Section(
            title: '数据存储',
            body:
                '你的照片、编辑结果、AI 生成图片和作品记录默认保存在本机 App 沙盒中，不会自动上传到开发者服务器。\n\n'
                'AI 生成的文字/图片、收藏和草稿记录也只保存在本机。卸载 App 或“清除本地作品”会删除这些数据。',
          ),
          const _Section(
            title: '第三方 AI 服务',
            body:
                'v1 采用 BYOK（Bring Your Own Key）模式：你在“AI 设置”中填写的 MiniMax / DeepSeek API Key 只保存在系统安全存储中。\n\n'
                '使用 AI 功能时，提示词、参考图和生成请求会由 App 直接发送给你选择的服务商，并受其隐私政策和计费规则约束。开发者不接收、不存储你的 API Key。',
          ),
          const _Section(
            title: 'AI 生成内容',
            body:
                'AI 生成内容会带有“AI 生成”标识，分享和导出时默认保留水印，App 不提供移除 AI 标识的能力。\n\n'
                '禁止使用本 App 生成违法、侵权、色情、暴力、仇恨、未成年人相关或其他违反服务商政策的内容。'
                'AI 输出可能不准确或不符合预期，请自行判断并承担使用责任。',
          ),
          const _Section(
            title: '设备权限',
            body:
                '相机：用于拍摄照片和实时构图辅助。\n'
                '相册：用于选择参考图、保存成片。\n'
                '运动传感器：用于水平仪和构图提示。\n'
                '以上权限均可在系统设置中关闭；关闭后对应功能不可用，但不影响其他本地功能。',
          ),
          const _Section(
            title: '你的权利',
            body:
                '你可以在“我的 → 清除本地作品”删除本机全部图片和记录，也可以在系统设置中清除 App 数据。\n\n'
                'v1 不创建开发者账号，因此不存在服务端账号数据；如后续接入云端账号，会提供账号注销和数据导出能力。',
          ),
          _Section(
            title: '反馈与举报',
            body: supportEmail.isEmpty
                ? '如发现违法、侵权或不当 AI 内容，请通过应用商店的评价/反馈渠道联系开发者，并附上作品 ID、提示词和问题说明。\n\n'
                      '上架构建可通过 --dart-define=SUPPORT_EMAIL=你的邮箱 配置专用反馈邮箱。'
                : '如发现违法、侵权或不当 AI 内容，请发送邮件至 $supportEmail，并附上作品 ID、提示词和问题说明。',
          ),
          const _Section(
            title: '协议范围',
            body:
                '本页面是 v1 的产品内说明，不替代正式《用户协议》和《隐私政策》。正式上架前需在商店后台提供完整协议文本和可公开访问的隐私政策链接。',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
