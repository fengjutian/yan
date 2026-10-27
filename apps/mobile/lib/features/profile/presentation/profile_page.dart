import 'package:ai_image_studio/app/theme_controller.dart';
import 'package:ai_image_studio/core/config/app_config.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:ai_image_studio/features/ai_settings/presentation/ai_settings_controller.dart';
import 'package:ai_image_studio/features/generate/data/local_creation_store.dart';
import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:ai_image_studio/features/share/presentation/share_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final user = state.user;
    final isGuest = user?.isGuest ?? true;
    final themeMode = ref.watch(themeModeProvider);
    final aiSettings = ref.watch(aiSettingsControllerProvider);

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
              icon: Icons.health_and_safety_outlined,
              label: '检查本地作品库',
              onTap: () => _repairLocalLibrary(context, ref),
            ),
            _ProfileTile(
              icon: Icons.delete_sweep_outlined,
              label: '清除本地作品',
              onTap: () => _clearLocalWorks(context, ref),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.offline_bolt_outlined),
              title: const Text('本地直连大模型'),
              subtitle: Text(
                !AppConfig.backendEnabled
                    ? '本地模式 · 使用本机 API Key 直连服务商'
                    : aiSettings.settings.preferLocal
                    ? '已开启 · 使用本机 API Key 直连服务商'
                    : '已关闭 · 上传与 AI 任务使用后端服务',
              ),
              value: AppConfig.backendEnabled
                  ? aiSettings.settings.preferLocal
                  : true,
              onChanged: (!AppConfig.backendEnabled || aiSettings.loading)
                  ? null
                  : (value) => ref
                        .read(aiSettingsControllerProvider.notifier)
                        .setPreferLocal(value),
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
              label: 'AI 创作方式',
              trailing: 'BYOK',
              onTap: () => _showMembershipDialog(context),
            ),
            _ProfileTile(
              icon: Icons.brightness_6_outlined,
              label: '主题设置',
              trailing: themeMode.label,
              onTap: () => _showThemeSheet(context, ref, themeMode),
            ),
            _ProfileTile(
              icon: Icons.auto_awesome_outlined,
              label: 'AI 设置',
              trailing: 'DeepSeek / MiniMax',
              onTap: () => context.push('/settings/ai'),
            ),
            _ProfileTile(
              icon: Icons.privacy_tip_outlined,
              label: '隐私与协议',
              trailing: 'AI 内容标识',
              onTap: () => context.push('/privacy'),
            ),
            const SizedBox(height: 16),
            if (!isGuest)
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

  Future<void> _clearLocalWorks(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除本地作品'),
        content: const Text('会删除本机保存的全部图片、缩略图和作品记录，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(localCreationStoreProvider).deleteAll();
      ref.invalidate(historyControllerProvider);
      try {
        final collections = ref.read(localCollectionServiceProvider);
        await collections.clear();
        ref.invalidate(favoritesProvider);
        ref.invalidate(draftsProvider);
      } catch (_) {
        // SharedPreferences 尚未初始化时，作品库清除仍应成功。
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('本地作品已清除')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清除失败：$error')));
    }
  }

  Future<void> _repairLocalLibrary(BuildContext context, WidgetRef ref) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('正在检查本地作品…')),
            ],
          ),
        ),
      ),
    );
    try {
      final report = await ref.read(localCreationStoreProvider).repair();
      ref.invalidate(historyControllerProvider);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(report.healthy ? '作品库状态正常' : '作品库检查完成'),
          content: Text(
            '有效作品：${report.validRecords}\n'
            '异常记录：${report.corruptRecords}\n'
            '缺失文件：${report.missingFiles}\n'
            '已清理临时文件：${report.removedTemporaryFiles}\n'
            '已清理空目录：${report.removedEmptyDirectories}'
            '${report.healthy ? '' : '\n\n异常目录已保留，避免误删可能恢复的用户文件。'}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('检查失败：$error')));
    }
  }

  void _showMembershipDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('AI 创作方式'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('· 当前为独立 BYOK 模式：AI 调用使用你本机的 MiniMax API Key'),
            SizedBox(height: 4),
            Text('· 拍摄、编辑、本地作品库免费使用，不依赖平台额度'),
            SizedBox(height: 4),
            Text('· 云端额度与订阅将在后续版本提供'),
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

  void _showThemeSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeMode selectedMode,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '主题设置',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              RadioGroup<ThemeMode>(
                groupValue: selectedMode,
                onChanged: (value) {
                  if (value == null) return;
                  ref.read(themeModeProvider.notifier).setThemeMode(value);
                  Navigator.of(sheetContext).pop();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final mode in ThemeMode.values)
                      RadioListTile<ThemeMode>(
                        value: mode,
                        title: Text(mode.label),
                        secondary: Icon(switch (mode) {
                          ThemeMode.system =>
                            Icons.settings_brightness_outlined,
                          ThemeMode.light => Icons.light_mode_outlined,
                          ThemeMode.dark => Icons.dark_mode_outlined,
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.nickname,
    required this.email,
    required this.isGuest,
  });

  final String nickname;
  final String email;
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
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: const Color(0xFF7B5152),
            child: Text(
              nickname.isEmpty ? '颜' : nickname.characters.first,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isGuest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('游客', style: TextStyle(fontSize: 10)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(
                      Icons.offline_bolt_outlined,
                      size: 14,
                      color: Color(0xFFE6A33A),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '本地优先 · BYOK',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
          Text(
            trailing!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        const Icon(Icons.chevron_right),
      ],
    ),
    onTap: onTap,
  );
}
