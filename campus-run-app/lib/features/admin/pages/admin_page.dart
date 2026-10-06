import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/admin_user.dart';
import '../../../data/models/password_reset_request.dart';
import '../../../data/repositories/admin_repository.dart';

/// 管理后台：找回密码 + 用户查询。
///
/// **为什么做成两个页签**：管理员的两类动作节奏完全不同 ——
/// 「待处理申请」是**有人等我**（需要尽快清空），
/// 「用户搜索」是**我要找某人**（按需使用）。
/// 混在一页里会让「还有几个人在等」这件事被搜索框淹没。
///
/// 权限说明：把入口藏起来只是 UI 便利，**不是安全边界**。
/// 真正的校验是服务端的 `@PreAuthorize("hasRole('ADMIN')")`。
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('管理后台'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: '找回密码申请'),
            Tab(text: '用户查询'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _RequestsTab(),
          _UsersTab(),
        ],
      ),
    );
  }
}

// ── 页签一：找回密码申请 ────────────────────────────────────────

class _RequestsTab extends ConsumerStatefulWidget {
  const _RequestsTab();

  @override
  ConsumerState<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends ConsumerState<_RequestsTab> {
  List<PasswordResetRequestItem>? _items;
  String? _error;
  bool _loading = true;
  bool _onlyPending = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(adminRepositoryProvider)
          .listRequests(status: _onlyPending ? PasswordResetRequestItem.statusPending : null);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '加载失败，请重试';
        _loading = false;
      });
    }
  }

  Future<void> _resolve(PasswordResetRequestItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置密码'),
        content: Text('确定要为「${item.nickname}」重置密码吗？\n\n'
            '系统会生成一个临时密码，旧密码立即失效，\n'
            '该用户所有设备都会被登出。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认重置')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final r = await ref.read(adminRepositoryProvider).resolveRequest(item.id);
      if (!mounted) return;
      await _showTemporaryPassword(r.nickname, r.temporaryPassword);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(e is ApiException ? e.message : '操作失败');
    }
  }

  Future<void> _reject(PasswordResetRequestItem item) async {
    try {
      await ref.read(adminRepositoryProvider).rejectRequest(item.id);
      if (!mounted) return;
      _toast('已拒绝「${item.nickname}」的申请');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(e is ApiException ? e.message : '操作失败');
    }
  }

  /// 展示临时密码。
  ///
  /// ⚠️ **这是唯一一次能看到明文的机会**：服务端只存 BCrypt 哈希。
  /// 所以这里同时给「复制」按钮，并明确提示要转达给用户。
  Future<void> _showTemporaryPassword(String nickname, String password) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('临时密码（只显示一次）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('用户：$nickname'),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: SelectableText(
                password,
                style: const TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: AppFontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '请把密码转达给该用户。关闭这个窗口后无法再查看 —— '
              '服务端只保存了加密后的值。',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: password));
              if (ctx.mounted) _toast('已复制到剪贴板');
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我已转达'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageWide,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '用户忘记密码时会在这里发起申请。\n'
                  '重置后请把临时密码当面或私聊转达给本人。',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageWide),
          child: Row(
            children: [
              FilterChip(
                label: const Text('只看待处理'),
                selected: _onlyPending,
                onSelected: (v) {
                  setState(() => _onlyPending = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ScrollableCenter(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ScrollableCenter(child: ErrorState(message: _error!, onRetry: _load));
    }
    final items = _items ?? const <PasswordResetRequestItem>[];
    if (items.isEmpty) {
      return ScrollableCenter(
        child: EmptyState(
          icon: Icons.check_circle_outline,
          title: _onlyPending ? '没有待处理的申请' : '还没有收到申请',
          subtitle: _onlyPending ? '所有申请都已处理完毕' : '用户忘记密码时会在这里出现',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageWide,
        0,
        AppSpacing.pageWide,
        AppSpacing.xl,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _RequestCard(
        item: items[i],
        onResolve: () => _resolve(items[i]),
        onReject: () => _reject(items[i]),
      ),
    );
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.item,
    required this.onResolve,
    required this.onReject,
  });

  final PasswordResetRequestItem item;
  final VoidCallback onResolve;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = item.isPending;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(nickname: item.nickname, size: 40),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nickname,
                      style: const TextStyle(
                        fontSize: AppFontSize.labelLg,
                        fontWeight: AppFontWeight.medium,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      item.phone,
                      style: const TextStyle(
                        fontSize: AppFontSize.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: item.status, label: item.statusLabel),
            ],
          ),
          if (item.note != null && item.note!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '说明：${item.note}',
              style: const TextStyle(
                fontSize: AppFontSize.caption,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (pending) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onReject, child: const Text('拒绝')),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(onPressed: onResolve, child: const Text('重置密码')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.label});

  final int status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PasswordResetRequestItem.statusPending => AppColors.primary,
      PasswordResetRequestItem.statusReset => AppColors.success,
      _ => AppColors.textHint,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: AppFontWeight.medium,
          color: color,
        ),
      ),
    );
  }
}

// ── 页签二：用户查询 ────────────────────────────────────────────

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final _controller = TextEditingController();
  List<AdminUser>? _items;
  String? _error;
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kw = _controller.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final r = await ref.read(adminRepositoryProvider).listUsers(keyword: kw);
      if (!mounted) return;
      setState(() {
        _items = r.list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '查询失败，请重试';
        _loading = false;
      });
    }
  }

  Future<void> _reset(AdminUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置密码'),
        content: Text('确定为「${user.nickname}」(${user.phone}) 重置密码吗？\n\n'
            '旧密码立即失效，该用户所有设备都会被登出。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final r = await ref.read(adminRepositoryProvider).resetPassword(user.userId);
      if (!mounted) return;
      await _showPassword(r.nickname, r.temporaryPassword);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : '操作失败')));
    }
  }

  Future<void> _showPassword(String nickname, String password) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('临时密码（只显示一次）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('用户：$nickname'),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: SelectableText(
                password,
                style: const TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: AppFontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: password));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(const SnackBar(content: Text('已复制')));
              }
            },
            child: const Text('复制'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: '手机号 / 昵称 / 专属 ID',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(onPressed: _loading ? null : _search, child: const Text('查询')),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ScrollableCenter(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ScrollableCenter(child: ErrorState(message: _error!, onRetry: _search));
    }
    if (!_searched) {
      return const ScrollableCenter(
        child: EmptyState(
          icon: Icons.person_search_outlined,
          title: '搜索用户',
          subtitle: '输入手机号、昵称或专属 ID 来找到需要帮助的用户\n留空直接查询会按注册时间倒序显示',
        ),
      );
    }
    final items = _items ?? const <AdminUser>[];
    if (items.isEmpty) {
      return const ScrollableCenter(
        child: EmptyState(
          icon: Icons.search_off,
          title: '没有找到用户',
          subtitle: '换个关键词试试，或者留空查询全部',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageWide,
        0,
        AppSpacing.pageWide,
        AppSpacing.xl,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final u = items[i];
        return AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.gap10),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(nickname: u.nickname, avatarUrl: u.avatarUrl, size: 44),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    u.nickname,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.labelLg,
                      fontWeight: AppFontWeight.medium,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (u.isAdmin) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.gap6,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: const Text(
                      '管理员',
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        color: AppColors.gold,
                        fontWeight: AppFontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              '${u.phone}   ID ${u.uniqueId}',
              style: const TextStyle(
                fontSize: AppFontSize.caption,
                color: AppColors.textSecondary,
              ),
            ),
            trailing: TextButton(
              onPressed: () => _reset(u),
              child: const Text('重置密码'),
            ),
          ),
        );
      },
    );
  }
}
