import 'package:campus_run_app/core/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('手机号校验', () {
    expect(Validators.validatePhone(''), isNotNull);
    expect(Validators.validatePhone('123'), isNotNull);
    expect(Validators.validatePhone('13800138000'), isNull);
  });

  test('密码校验', () {
    expect(Validators.validatePassword(''), isNotNull);
    expect(Validators.validatePassword('123'), isNotNull);
    expect(Validators.validatePassword('secret123'), isNull);
  });
}
