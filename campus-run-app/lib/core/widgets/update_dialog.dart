import 'package:flutter/material.dart';

import '../../data/repositories/app_version_repository.dart';
import '../platform/external_link.dart';
import '../platform/install_permission.dart';
import '../theme/app_theme.dart';
import '../update/app_update_service.dart';

/// 发现新版本时的提示。
///
/// 做成独立的 StatefulWidget 而不是就地 `showDialog` 是有原因的：
/// 下载过程中要持续刷新进度，而 `AlertDialog` 的 builder 不会因为
/// 外部变量变化而重建 —— 那样进度条会一直停在 0%。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info, this.force = false});

  final AppVersionInfo info;

  /// 强制更新：隐藏「稍后」，用户只能更新（或直接退出 App）。
  ///
  /// 由**服务端**决定，不由客户端猜：`version.json` 里的 `minSupported`
  /// 高于当前版本时，服务端会在每个响应上带 `X-App-Update-Required: true`，
  /// 并对该客户端直接返回 426。这样「强制」是一处可控的策略，
  /// 而不是发一个客户端版本才能改的行为。
  final bool force;

  /// 弹出更新提示；返回 true 表示用户已完成「下载并唤起安装器」。
  static Future<bool> show(BuildContext context, AppVersionInfo info,
      {bool force = false}) async {
    final result = await showDialog<bool>(
      context: context,
      // 下载中不允许点外面关掉：那会留下一个下载到一半的文件，
      // 而且用户会以为已经取消了（实际还在下）。
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info, force: force),
    );
    return result ?? false;
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  UpdateStatus _status = const UpdateStatus();
  bool _downloading = false;

  /// 本机版本号。判断「是否低于服务端下限」必须跟**自己**比，
  /// 而不是拿服务端两个字段互相比 —— 后者是上面修掉的那个 bug。
  String? _myVersion;

  @override
  void initState() {
    super.initState();
    AppUpdateService.instance.currentVersion().then((v) {
      if (mounted) setState(() => _myVersion = v);
    }).catchError((Object _) {});
  }

  bool get _busy => _downloading;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _status = const UpdateStatus(stage: UpdateStage.downloading);
    });

    final error = await AppUpdateService.instance.downloadAndInstall(
      widget.info,
      onProgress: (s) {
        if (!mounted) return;
        setState(() => _status = s);
      },
    );

    if (!mounted) return;
    setState(() {
      _downloading = false;
      if (error != null) {
        _status = UpdateStatus(stage: UpdateStage.failed, message: error);
      }
    });
  }

  void _close() {
    // 下载中关闭 = 取消下载。不这么做的话，用户关掉弹窗后流量还在跑。
    if (_busy) AppUpdateService.instance.cancel();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    // 是否强制更新。
    //
    // ⚠️ 这里原本写的是
    //     `info.minSupported.isNotEmpty && isVersionNewer(info.latest, info.minSupported)`
    //   —— **判断对象错了**：它比较的是「服务端最新版」与「服务端下限」，
    //   完全没看用户本机版本。只要 minSupported 一配上，
    //   所有人都看不到「稍后」，包括已经是最新版的用户。
    //
    // 正确语义有三种来源，任一成立即强制：
    //   1. 服务端在响应头显式要求（X-App-Update-Required）—— 权威；
    //   2. 本机版本低于服务端下限（用 minSupported 自己算，客户端也能自证）；
    //   3. 服务端下次会以 426 拒绝请求 —— 与第 2 条等价，此处不重复判断。
    final isMandatory = widget.force ||
        (info.minSupported.isNotEmpty &&
            isVersionNewer(info.minSupported, _myVersion ?? ''));
    final failed = _status.stage == UpdateStage.failed;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update_alt, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('发现新版本 ${info.latest}')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '安装包 ${info.sizeLabel}',
              style: const TextStyle(
                fontSize: AppFontSize.caption,
                color: AppColors.textSecondary,
              ),
            ),
            if (info.changelog.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Text(
                '更新内容',
                style: TextStyle(
                  fontSize: AppFontSize.body,
                  fontWeight: AppFontWeight.medium,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                info.changelog,
                style: const TextStyle(
                  fontSize: AppFontSize.caption,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (_busy || _status.stage == UpdateStage.downloading)
              _buildProgress()
            else if (failed)
              _buildError(_status.message ?? '下载失败')
            else
              _buildInstallHint(),
          ],
        ),
      ),
      actions: _buildActions(isMandatory),
    );
  }

  Widget _buildProgress() {
    final progress = _status.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // progress 为 null 表示服务端没给 Content-Length，
        // 此时用不确定态进度条，而不是假装进度 0%。
        LinearProgressIndicator(value: progress),
        const SizedBox(height: AppSpacing.sm),
        Text(
          progress == null
              ? '正在下载 ${_status.receivedLabel}…'
              : '正在下载 ${_status.receivedLabel} / ${_status.totalLabel}'
                  '（${(progress * 100).toStringAsFixed(0)}%）',
          style: const TextStyle(
            fontSize: AppFontSize.caption,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          '下载完成后会弹出系统安装界面，需要你点一下「安装」。',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }

  Widget _buildError(String message) {
    // 「安装包已下载完成，但系统还不允许安装」这种情况需要额外给一个
    // 一键跳转按钮 —— 用户看着这段文字是找不到「安装未知应用」在哪的。
    //
    // 判断方式很土（比字符串）但足够稳：这条文案只有权限分支会产出，
    // 不会与别的错误混淆；为了它给错误类型加一层枚举得不偿失。
    final needsPermission = message.contains('允许安装未知应用');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    height: 1.5,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          if (needsPermission) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => InstallPermission.openSettings(),
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('去授权'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 还没开始下载时的说明。
  ///
  /// 这里必须**提前告知**「会弹系统安装界面、可能要授权安装未知应用」——
  /// 用户突然被跳到系统设置页会以为是 App 出问题了。
  Widget _buildInstallHint() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '更新方式',
          style: TextStyle(
            fontSize: AppFontSize.body,
            fontWeight: AppFontWeight.medium,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          '下载完成后，系统会弹出安装界面，点「安装」即可。\n'
          '如果提示不允许安装，请到「设置 → 应用 → 行迹 → 安装未知应用」'
          '里允许后再试一次。',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            height: 1.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // 应用内下载偶尔会受网络影响；给一个绕开本 App 的备用入口，
        // 用户至少有一条「自己去下载」的路。
        _buildRepoEntry(),
      ],
    );
  }

  /// 「从 GitHub 下载」入口。
  ///
  /// ## 为什么要有它
  ///
  /// 应用内更新是主路径，但它依赖「能连上本项目的服务器」。
  /// 服务器在国内、带宽有限（实测约 0.4 MB/s），换网络或服务器异常时
  /// 应用内下载就成了单点。GitHub 上同步发布了每个版本的 APK，
  /// 可以作为**独立的备用通道**。
  ///
  /// ⚠️ 不把它做成默认下载源：GitHub 在国内的可达性不稳定
  /// （实测部分网络完全连不上、走代理也只有 0.28 MB/s，
  /// 而服务器直连是 0.47 MB/s）。它的价值是「多一条路」，不是「更快」。
  Widget _buildRepoEntry() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _openRepo,
        icon: const Icon(Icons.code, size: 16),
        label: const Text('从 GitHub 下载'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Future<void> _openRepo() async {
    final ok = await ExternalLink.open(ProjectLinks.releases);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没能打开浏览器，请手动访问 GitHub 上的项目仓库')),
    );
  }

  List<Widget> _buildActions(bool isMandatory) {
    final failed = _status.stage == UpdateStage.failed;

    if (_busy || _status.stage == UpdateStage.downloading) {
      return [
        TextButton(onPressed: _close, child: const Text('取消下载')),
      ];
    }

    return [
      // 强制更新时不提供「稍后」——那是修复严重缺陷的通道。
      if (!isMandatory)
        TextButton(onPressed: _close, child: const Text('稍后')),
      FilledButton(
        onPressed: _startDownload,
        child: Text(failed ? '重试' : '立即更新'),
      ),
    ];
  }
}
