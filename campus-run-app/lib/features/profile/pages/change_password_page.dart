import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

/// 修改密码。
///
/// 交互要点：
/// - 三个输入框都带显隐切换：输密码时看不到自己输了什么，容易输错
/// - 前端先做一次本地校验（旧密码非空、新密码长度、两次一致），
///   避免明知会失败的请求也打到服务端；**服务端仍会再校验一遍**（前端校验不可信）
/// - 成功后服务端会吊销全部 refresh token，本页负责提示「需要重新登录」并回登录页
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _oldVisible = false;
  bool _newVisible = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).changePassword(
            _oldController.text,
            _newController.text,
          );
      if (!mounted) return;
      // 改密成功 = 全端下线。必须明确告知，否则用户会以为「怎么突然被登出了」。
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('密码已修改'),
          content: const Text('为保证安全，其他设备上的登录已失效。\n请用新密码重新登录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      // authProvider 已被置空，路由守卫会把用户带回登录页，这里无需手动跳转。
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '修改失败，请稍后重试';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          children: [
            _PasswordField(
              controller: _oldController,
              label: '当前密码',
              hint: '请输入当前使用的密码',
              visible: _oldVisible,
              onToggle: () => setState(() => _oldVisible = !_oldVisible),
              validator: (v) =>
                  (v == null || v.isEmpty) ? '请输入当前密码' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _PasswordField(
              controller: _newController,
              label: '新密码',
              hint: '8-64 位，建议混合字母与数字',
              visible: _newVisible,
              onToggle: () => setState(() => _newVisible = !_newVisible),
              validator: (v) {
                if (v == null || v.isEmpty) return '请输入新密码';
                // 与注册的下限保持一致：两侧规则不同会让用户困惑
                if (v.length < 8) return '新密码至少 8 位';
                if (v.length > 64) return '新密码不能超过 64 位';
                if (v == _oldController.text) return '新密码不能与当前密码相同';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _PasswordField(
              controller: _confirmController,
              label: '确认新密码',
              hint: '再次输入新密码',
              visible: _newVisible,
              onToggle: () => setState(() => _newVisible = !_newVisible),
              validator: (v) {
                if (v == null || v.isEmpty) return '请再次输入新密码';
                if (v != _newController.text) return '两次输入的新密码不一致';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: AppFontSize.body,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
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
                    : const Text('确认修改'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '修改成功后，其他设备上的登录会立即失效，需要用新密码重新登录。',
              style: TextStyle(
                fontSize: AppFontSize.hint,
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 带显隐切换的密码输入框。
///
/// 抽出来是因为三个框的样式与行为完全一致，复制三份很容易改漏其中一个。
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.visible,
    required this.onToggle,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool visible;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          tooltip: visible ? '隐藏密码' : '显示密码',
          onPressed: onToggle,
        ),
      ),
    );
  }
}
