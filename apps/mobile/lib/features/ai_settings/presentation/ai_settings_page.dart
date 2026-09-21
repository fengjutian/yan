import 'package:ai_image_studio/features/ai_settings/data/ai_settings_repository.dart';
import 'package:ai_image_studio/features/ai_settings/presentation/ai_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AISettingsPage extends ConsumerStatefulWidget {
  const AISettingsPage({super.key});

  @override
  ConsumerState<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends ConsumerState<AISettingsPage> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  bool _synced = false;
  bool _obscureKey = true;

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiSettingsControllerProvider);
    if (!state.loading && !_synced) {
      _synced = true;
      _baseUrl.text = state.settings.baseUrl;
      _model.text = state.settings.model;
      _apiKey.text = state.settings.apiKey;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.bolt_rounded),
                          SizedBox(width: 8),
                          Text('MiniMax 国内线路',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          '配置仅保存在本机安全存储中。启用后，AI 帮写和分享文案会优先由 APP 直连 MiniMax，失败时自动回退服务端。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用 MiniMax'),
                  subtitle: const Text('使用你自己的 API Key'),
                  value: state.settings.enabled,
                  onChanged: (value) => _update(enabled: value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('优先本地调用 AI'),
                  subtitle: const Text('APP 直连优先，服务端作为备用'),
                  value: state.settings.preferLocal,
                  onChanged: state.settings.enabled
                      ? (value) => _update(preferLocal: value)
                      : null,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKey,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: '填写 MiniMax API Key',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(_obscureKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                    ),
                  ),
                  onChanged: (_) => _update(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '接口地址',
                    helperText: '默认使用 MiniMax 中国大陆域名',
                  ),
                  onChanged: (_) => _update(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '模型名称'),
                  onChanged: (_) => _update(),
                ),
                if (state.message != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    state.message!,
                    style: TextStyle(
                      color: state.isError
                          ? Theme.of(context).colorScheme.error
                          : Colors.green.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.testing || state.saving
                          ? null
                          : () {
                              _update();
                              ref
                                  .read(aiSettingsControllerProvider.notifier)
                                  .test();
                            },
                      child: Text(state.testing ? '测试中…' : '测试连接'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: state.testing || state.saving
                          ? null
                          : () async {
                              _update();
                              await ref
                                  .read(aiSettingsControllerProvider.notifier)
                                  .save();
                            },
                      child: Text(state.saving ? '保存中…' : '保存设置'),
                    ),
                  ),
                ]),
              ],
            ),
    );
  }

  void _update({bool? enabled, bool? preferLocal}) {
    final current = ref.read(aiSettingsControllerProvider).settings;
    ref.read(aiSettingsControllerProvider.notifier).update(AISettings(
          enabled: enabled ?? current.enabled,
          preferLocal: preferLocal ?? current.preferLocal,
          baseUrl: _baseUrl.text,
          model: _model.text,
          apiKey: _apiKey.text,
        ));
  }
}
