/// 表单校验，供登录/注册/后续改密码等页面复用。
class Validators {
  Validators._();

  /// 手机号规则，**必须与后端 `RegisterRequest` 上的 `@Pattern` 完全一致**：
  /// `^1[3-9]\d{9}$`。
  ///
  /// ⚠️ 真实问题：这里原本只校验 `^\d{11}$`（11 位数字），比后端宽松。
  /// 于是 `11111111111` 通过了本地校验、发到后端才被拒，
  /// 用户看到的是一句笼统的「参数错误」，完全不知道是号段不合法 ——
  /// 本地校验存在的意义就是**在用户还看着输入框时**给出准确原因。
  static final RegExp _phone = RegExp(r'^1[3-9]\d{9}$');

  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入手机号';
    final v = value.trim();
    if (v.length != 11 || !RegExp(r'^\d+$').hasMatch(v)) {
      return '手机号应为 11 位数字';
    }
    if (!_phone.hasMatch(v)) {
      // 明确说清是号段问题，而不是笼统的「格式不正确」——
      // 否则用户会一直以为是位数或空格的问题。
      return '手机号号段不正确（须以 13–19 开头）';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return '请输入密码';
    if (value.length < 6) return '密码至少 6 位';
    if (value.length > 32) return '密码最长 32 位';
    return null;
  }

  static String? validateNickname(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入昵称';
    if (value.trim().length > 30) return '昵称最长 30 个字符';
    return null;
  }
}
