import 'package:ai_image_studio/core/compliance/privacy_consent.dart';
import 'package:ai_image_studio/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// 首次启动的隐私政策确认页：不同意就退出，同意后才进入 App。
///
/// 商店审核会检查“同意前不得申请权限/收集信息”，所以这一页不能出现
/// 相机预览、网络请求或任何 SDK 初始化。
class PrivacyConsentPage extends StatelessWidget {
  const PrivacyConsentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '欢迎使用颜 Studio',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                '请阅读并同意以下条款后开始使用。',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(height: 1.6),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Bullet(text: '照片、编辑结果和作品保存在本机，不会上传到开发者服务器。'),
                      const _Bullet(
                        text: '相机、相册、运动传感器权限只在你使用对应功能时申请，可随时在系统设置中关闭。',
                      ),
                      const _Bullet(
                        text:
                            'AI 生成功能使用你自己配置的 MiniMax / DeepSeek API Key，请求直接发送给对应服务商。',
                      ),
                      const _Bullet(text: 'AI 生成内容会保留“AI 生成”标识，分享与导出不提供移除能力。'),
                      const _Bullet(text: '你可以随时在“我的”中清除本机全部作品与数据。'),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _DocLink(
                            label: '《隐私政策》',
                            url: AppConfig.privacyPolicyUrl.trim(),
                            fallbackRoute: '/privacy',
                          ),
                          _DocLink(
                            label: '《用户协议》',
                            url: AppConfig.termsUrl.trim(),
                            fallbackRoute: '/privacy',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '点击“同意并继续”即表示你已阅读并同意上述条款。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await PrivacyConsent.accept();
                    if (!context.mounted) return;
                    context.go('/home');
                  },
                  child: const Text('同意并继续'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: PrivacyConsent.declineAndExit,
                  child: const Text('不同意并退出'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('·  '),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocLink extends StatelessWidget {
  const _DocLink({
    required this.label,
    required this.url,
    required this.fallbackRoute,
  });

  final String label;
  final String url;
  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
      onPressed: () async {
        if (url.isEmpty) {
          context.push(fallbackRoute);
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          messenger.showSnackBar(const SnackBar(content: Text('无法打开链接，请稍后重试')));
        }
      },
      child: Text(label),
    );
  }
}
