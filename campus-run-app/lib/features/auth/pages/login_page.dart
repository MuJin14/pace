import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../providers/auth_provider.dart';

/// 登录页（极简白底风）。
///
/// 版式全部由 [AuthScaffold] 提供，本页只管字段与提交逻辑 ——
/// 与注册页共享同一套版式，不会再出现两页样式不一致。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;

  /// 是否已同意用户协议与隐私政策。
  ///
  /// **为什么必须有**：本 App 收集定位与手机号，属《个人信息保护法》与
  /// 应用商店审核的强制项 —— 必须由用户**主动勾选**表示同意，
  /// 只放一个可点的文字链接是不够的。
  bool _agreed = false;

  /// 密码框是否正在被编辑 —— 驱动背景「闭眼」。
  ///
  /// 用户输密码时，跑道上的圆点压扁成一条横线，与上方的跑道弧线
  /// 组成一只闭着的眼睛，表达「密码是安全的，没人看着」。
  bool _passwordFocused = false;

  @override
  void dispose() {
    _phoneController.dispose();
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
      await ref.read(authProvider.notifier).login(
            _phoneController.text.trim(),
            _passwordController.text,
          );
    } on ApiException catch (e) {
      _show(e.message);
    } catch (_) {
      _show('登录失败，请稍后重试');
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
      slogan: '记录你的每一段行程',
      title: '欢迎回来',
      subtitle: '登录后继续记录你的每一次运动',
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
                controller: _passwordController,
                hint: '密码',
                icon: Icons.lock_outline,
                obscure: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: Validators.validatePassword,
                // 进入密码框 → 背景闭眼
                onFocusChange: (focused) =>
                    setState(() => _passwordFocused = focused),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: AuthTextLink(
                  label: '忘记密码？',
                  fontSize: AppFontSize.caption,
                  bold: false,
                  onTap: () => context.push('/forgot-password'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AgreementCheckbox(
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              AuthPrimaryButton(
                label: '登录',
                loading: _submitting,
                onPressed: _submit,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthSwitchRow(
                prompt: '还没有账号？',
                actionLabel: '立即注册',
                onAction: () => context.push('/register'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
