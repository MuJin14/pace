import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/models/password_reset_request.dart';
import '../../../data/repositories/auth_repository.dart';

/// 忘记密码。
///
/// **为什么是「申请」而不是「自助重置」**：App 没有邮箱字段、也没有短信服务，
/// 无法验证「申请的人真的是账号主人」。硬做一个不需要验证的重置等于任何人都能改别人密码。
/// 所以这里的做法是：用户提交申请 → 管理员在后台看到 → 重置后把临时密码转达本人。
/// 代价是**不是即时**的，但这是当前唯一既安全又能用的方案。
///
/// ⚠️ 提交成功**只代表「已收到」**，不代表账号存在 ——
/// 服务端对未注册手机号也返回成功，否则这个接口就成了手机号枚举器。
/// 所以文案不能说「已找到你的账号」。
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();

  bool _submitting = false;
  bool _submitted = false;
  String? _phoneError;

  /// 已提交过申请的用户，登录后可在这里查上一次的处理状态。
  PasswordResetRequestItem? _latest;

  @override
  void initState() {
    super.initState();
    _loadLatest();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 尝试读取「我上一次的申请」——**未登录时必然 401，这很正常**，
  /// 所以整个失败路径静默处理，不打扰用户。
  Future<void> _loadLatest() async {
    try {
      final data = await ref.read(authRepositoryProvider).myPasswordResetRequest();
      if (!mounted || data == null) return;
      setState(() => _latest = PasswordResetRequestItem.fromJson(data));
    } catch (_) {
      // 未登录 / 网络问题都不该让这个页面报错
    }
  }

  bool _validate() {
    final phone = _phoneController.text.trim();
    String? error;
    if (phone.isEmpty) {
      error = '请输入手机号';
    } else if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      error = '请输入 11 位手机号';
    }
    setState(() => _phoneError = error);
    return error == null;
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(authRepositoryProvider).submitPasswordResetRequest(
            _phoneController.text.trim(),
            note: _noteController.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '提交失败，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('忘记密码')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageWide),
        children: [
          if (_latest != null) ...[
            _LatestStatusCard(item: _latest!),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_submitted)
            const _SubmittedCard()
          else
            _buildForm(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '怎么找回',
                style: TextStyle(
                  fontSize: AppFontSize.subtitle,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '提交申请后，管理员会在后台看到，帮你重置一个临时密码。\n'
                '拿到临时密码后用它登录，再在「我的 → 修改密码」里改成自己的密码。',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          onChanged: (_) => setState(() => _phoneError = null),
          decoration: InputDecoration(
            labelText: '注册时的手机号',
            hintText: '11 位手机号',
            counterText: '',
            errorText: _phoneError,
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _noteController,
          maxLength: 100,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '情况说明（选填）',
            hintText: '例如：换手机了，登不上',
            prefixIcon: Icon(Icons.edit_note_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: AppSpacing.xxl,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('提交申请'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          '提示：如果你的账号是管理员帮忙开的，直接把这句话转达给管理员会更快。',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}

class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          const Icon(Icons.mark_email_read_outlined,
              size: 48, color: AppColors.success),
          const SizedBox(height: AppSpacing.md),
          const Text(
            '申请已提交',
            style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: AppFontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '管理员会在后台看到你的申请并帮你重置密码。\n'
            '拿到临时密码后用它登录，再去「我的 → 修改密码」改成自己的密码。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回登录'),
          ),
        ],
      ),
    );
  }
}

/// 展示「我上一次申请」的状态。
///
/// 有了它，用户不必反复提交 —— 能看到「已重置」就知道可以去取临时密码了。
class _LatestStatusCard extends StatelessWidget {
  const _LatestStatusCard({required this.item});

  final PasswordResetRequestItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.status) {
      PasswordResetRequestItem.statusPending => AppColors.primary,
      PasswordResetRequestItem.statusReset => AppColors.success,
      _ => AppColors.textHint,
    };
    final hint = switch (item.status) {
      PasswordResetRequestItem.statusPending => '管理员还没处理，请稍等；不用重复提交。',
      PasswordResetRequestItem.statusReset => '你的密码已被重置，请向管理员索取临时密码。',
      _ => '这次申请被拒绝。如果确实需要，请联系管理员说明情况。',
    };
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '你最近一次申请：${item.statusLabel}',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.medium,
                    color: color,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
