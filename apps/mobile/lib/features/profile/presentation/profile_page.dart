import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final user = state.user;
    final isGuest = user?.id.startsWith('guest_') ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: ref.read(authControllerProvider.notifier).refreshProfile,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(
              nickname: user?.nickname ?? '游客',
              email: user?.email ?? '未登录可继续创作',
              credits: user?.creditsBalance ?? 0,
              isGuest: isGuest,
            ),
            const SizedBox(height: 16),
            _SectionTitle('作品'),
            _ProfileTile(
              icon: Icons.favorite_outline,
              label: '我的收藏',
              onTap: () => context.push('/me/favorites'),
            ),
            _ProfileTile(
              icon: Icons.edit_note,
              label: '草稿箱',
              onTap: () => context.push('/me/drafts'),
            ),
            const SizedBox(height: 16),
            _SectionTitle('账户'),
            _ProfileTile(
              icon: Icons.workspace_premium_outlined,
              label: '会员额度',
              trailing: isGuest ? '游客模式' : '普通用户',
              onTap: () => _showMembershipDialog(context),
            ),
            _ProfileTile(
              icon: Icons.tune,
              label: '偏好设置',
              trailing: '默认 1:1 / 4 张',
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('敬请期待')),
              ),
            ),
            _ProfileTile(
              icon: Icons.privacy_tip_outlined,
              label: '隐私与协议',
              trailing: 'AI 内容标识',
              onTap: () => _showPrivacySheet(context),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: state.submitting
                  ? null
                  : () => ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMembershipDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('会员额度'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('· 游客:每日 10 张免费 AI 成片,按自然日恢复'),
            SizedBox(height: 4),
            Text('· 普通用户:每月赠送 100 张,过期不滚存'),
            SizedBox(height: 4),
            Text('· 套餐订单模型已就绪,真实支付稍后开放'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showPrivacySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('隐私与协议',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            SizedBox(height: 12),
            Text('· 默认不公开作品,不使用用户照片训练模型'),
            SizedBox(height: 4),
            Text('· 生成结果保留「颜 · AI 生成」水印,不可关闭'),
            SizedBox(height: 4),
            Text('· 分享时可关闭 EXIF 中的位置/设备元数据'),
            SizedBox(height: 4),
            Text('· 完整协议请前往设置页查看(筹备中)'),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.nickname,
    required this.email,
    required this.credits,
    required this.isGuest,
  });

  final String nickname;
  final String email;
  final int credits;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8F6F1), Color(0xFFEFE6D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: const Color(0xFF7B5152),
          child: Text(
            nickname.isEmpty ? '颜' : nickname.characters.first,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(width: 6),
                if (isGuest)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('游客', style: TextStyle(fontSize: 10)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.brightness_5_rounded,
                    size: 14, color: Color(0xFFE6A33A)),
                const SizedBox(width: 4),
                Text('剩余 $credits 次',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null)
              Text(trailing!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      )),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      );
}