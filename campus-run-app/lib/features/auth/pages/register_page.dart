import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../providers/auth_provider.dart';

/// 注册页（极简白底风），与登录页共用 [AuthScaffold] 版式。
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;

  /// 见 `login_page.dart` 的说明 —— 注册同样必须主动同意。
  bool _agreed = false;

  /// 密码框是否正在被编辑 —— 驱动背景「闭眼」（见登录页的说明）。
  bool _passwordFocused = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      _show('请先阅读并同意《用户协议与隐私政策》');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await ref.read(authProvider.notifier).register(
            _phoneController.text.trim(),
            _passwordController.text,
            _nicknameController.text.trim(),
          );
    } on ApiException catch (e) {
      _show(e.message);
    } catch (_) {
      _show('注册失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      slogan: '和同学一起，跑起来',
      title: '创建账号',
      subtitle: '注册后自动生成你的专属 ID',
      eyeClosed: _passwordFocused,
      formChildren: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                controller: _phoneController,
                hint: '手机号',
                icon: Icons.phone_android,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: Validators.validatePhone,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthField(
                controller: _nicknameController,
                hint: '昵称',
                icon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                maxLength: 30,
                validator: Validators.validateNickname,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthField(
                controller: _passwordController,
                hint: '密码（至少 6 位）',
                icon: Icons.lock_outline,
                obscure: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: Validators.validatePassword,
                onFocusChange: (focused) =>
                    setState(() => _passwordFocused = focused),
              ),
              const SizedBox(height: AppSpacing.md),
              AgreementCheckbox(
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              AuthPrimaryButton(
                label: '注册',
                loading: _submitting,
                onPressed: _submit,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthSwitchRow(
                prompt: '已有账号？',
                actionLabel: '去登录',
                // pop 回到登录页；若注册页是被深链直接打开的（栈里只有它），
                // pop 无处可去，退化成 go 登录页，避免按钮点了没反应。
                onAction: () =>
                    context.canPop() ? context.pop() : context.go('/login'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
