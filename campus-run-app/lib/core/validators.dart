/// 表单校验，供登录/注册/后续改密码等页面复用。
class Validators {
  Validators._();

  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入手机号';
    if (!RegExp(r'^\d{11}$').hasMatch(value.trim())) return '手机号格式不正确';
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return '请输入密码';
    if (value.length < 6) return '密码至少 6 位';
    return null;
  }

  static String? validateNickname(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入昵称';
    return null;
  }
}
