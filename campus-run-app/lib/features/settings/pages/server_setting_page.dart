import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';

/// 服务器地址设置页。
///
/// **为什么需要这个页面**：API 地址原先只能编译期注入，换一次网络
/// （宿舍 WiFi / 校园网 / 手机热点）就要重新构建安装一遍，而调试时 IP 几乎每次都在变。
/// 现在可以在 App 内直接改，保存后立即生效（写入本地，重启仍有效）。
class ServerSettingPage extends ConsumerStatefulWidget {
  const ServerSettingPage({super.key});

  @override
  ConsumerState<ServerSettingPage> createState() => _ServerSettingPageState();
}

class _ServerSettingPageState extends ConsumerState<ServerSettingPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: currentBaseUrl(ref));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({bool useDefault = false}) async {
    final ok = await ref
        .read(serverBaseUrlProvider.notifier)
        .save(useDefault ? null : _controller.text);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('地址格式不对，示例：192.168.1.5:8080')));
      return;
    }
    if (useDefault) _controller.text = currentBaseUrl(ref);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已保存：${currentBaseUrl(ref)}')));
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(serverBaseUrlProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('服务器地址')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前地址',
                    style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(current,
                    style: TextStyle(
                        fontSize: AppFontSize.subtitle,
                        fontWeight: AppFontWeight.medium,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: '例如 10.167.141.58:8080',
              helperText: '可省略 http://，会自动补上',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: '保存', onPressed: _save),
          const SizedBox(height: AppSpacing.sm),
          AppTextAction(
            label: '恢复默认地址',
            onTap: () => _save(useDefault: true),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('怎么填',
                    style: TextStyle(
                        fontSize: AppFontSize.labelLg,
                        fontWeight: AppFontWeight.medium,
                        color: AppColors.textPrimary)),
                const SizedBox(height: AppSpacing.sm),
                _hint('手机和电脑在同一个 WiFi 下时，填电脑的局域网 IP + :8080'),
                _hint('电脑上查 IP：PowerShell 里执行 ipconfig，看「无线局域网适配器 WLAN」的 IPv4 地址'),
                _hint('数据线调试时也可以填 127.0.0.1:8080（需先执行 adb reverse tcp:8080 tcp:8080）'),
                _hint('换网络后 IP 会变，回来这里改一下即可，不用重新安装'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextAction(label: '返回', onTap: () => context.pop()),
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('· ',
                style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textHint)),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: AppColors.textSecondary,
                      height: 1.5)),
            ),
          ],
        ),
      );
}
