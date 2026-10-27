import 'package:ai_image_studio/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 独立客户端的隐私、协议、AI 内容标识与备案信息说明。
///
/// 商店上架时仍需在开放平台后台填写可公开访问的《隐私政策》链接；
/// 构建时传 `--dart-define=PRIVACY_POLICY_URL=...` 可让 App 内直接打开同一份文本。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final supportEmail = AppConfig.supportEmail.trim();
    final beianNumber = AppConfig.beianNumber.trim();
    final appVersion = AppConfig.appVersion.trim();
    final developerName = AppConfig.developerName.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('隐私与协议')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Section(
            title: '数据存储',
            body: AppConfig.backendEnabled
                ? '本地模式（默认）：你的照片、编辑结果、AI 生成图片和作品记录保存在本机 App 沙盒中，不会自动上传到开发者服务器。\n\n'
                      '如果在“我的”中关闭“本地直连大模型”，客户端会改用后端服务，参考图和任务会通过后端接口上传；该模式目前用于开发与后续云端版本预留。\n\n'
                      '卸载 App 或“清除本地作品”会删除本机数据。'
                : '本地模式：你的照片、编辑结果、AI 生成图片和作品记录保存在本机 App 沙盒中，不会上传到开发者服务器。\n\n'
                      '卸载 App 或“清除本地作品”会删除本机数据。',
          ),
          const _Section(
            title: '第三方 AI 服务',
            body:
                '本 App 采用 BYOK（Bring Your Own Key）模式：你在“AI 设置”中填写的 MiniMax / DeepSeek API Key 只保存在系统安全存储中。\n\n'
                '提示词、参考图和生成请求由 App 直接发送给你选择的服务商，并受其隐私政策和计费规则约束。开发者不接收、不存储你的 API Key。\n\n'
                '除你选择的服务商外，App 不会把任何内容发送给其他第三方。',
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
                '相册（读取）：用于选择参考图和待编辑照片。\n'
                '相册（写入/媒体库）：用于把成片保存到系统相册。\n'
                '运动传感器：用于水平仪和构图提示。\n'
                '以上权限均可在系统设置中关闭；关闭后对应功能不可用，但不影响其他本地功能。',
          ),
          const _Section(
            title: '你的权利',
            body:
                '你可以在“我的 → 清除本地作品”删除本机全部图片和记录，也可以在系统设置中清除 App 数据。\n\n'
                '本 App 默认不要求登录，不含手机号、邮箱等账号信息采集。如需删除数据或行使其他权利，请通过下方反馈渠道联系开发者。',
          ),
          _Section(
            title: '反馈与举报',
            body: supportEmail.isEmpty
                ? '如发现违法、侵权或不当 AI 内容，请通过应用商店的评价/反馈渠道联系开发者，并附上作品 ID、提示词和问题说明。'
                : '如发现违法、侵权或不当 AI 内容，请发送邮件至 $supportEmail，并附上作品 ID、提示词和问题说明。',
          ),
          _Section(
            title: '备案与开发者信息',
            body: [
              if (developerName.isNotEmpty) '开发者：$developerName',
              if (beianNumber.isNotEmpty) '备案号：$beianNumber',
              if (appVersion.isNotEmpty) '版本：$appVersion',
              if (developerName.isEmpty &&
                  beianNumber.isEmpty &&
                  appVersion.isEmpty)
                '商店版本会在“关于”中展示开发者主体与备案信息。',
            ].join('\n'),
          ),
          const _Section(
            title: '协议范围',
            body:
                '本页面是 App 内的产品说明，不替代正式《用户协议》和《隐私政策》。'
                '正式文本可在下方打开；如链接不可用，请以应用商店页面公示的协议为准。',
          ),
          if (AppConfig.privacyPolicyUrl.trim().isNotEmpty)
            _LinkTile(
              icon: Icons.policy_outlined,
              label: '查看《隐私政策》',
              url: AppConfig.privacyPolicyUrl.trim(),
            ),
          if (AppConfig.termsUrl.trim().isNotEmpty)
            _LinkTile(
              icon: Icons.description_outlined,
              label: '查看《用户协议》',
              url: AppConfig.termsUrl.trim(),
            ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.label, required this.url});

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          messenger.showSnackBar(
            const SnackBar(content: Text('无法打开链接，请检查系统浏览器')),
          );
        }
      },
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
