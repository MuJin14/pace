import 'package:campus_run_app/data/models/user.dart';
import 'package:campus_run_app/data/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// 性别 / 年龄的可见性语义。
///
/// **为什么要单独测**：这是隐私相关字段，「不公开」必须表现为
/// **字段为 null**，而不是 0 或占位值 ——
/// 一旦前端把 null 兜底成 0，用户就能从数字上看出「对方设置了但不公开」，
/// 等于隐私开关形同虚设。
void main() {
  group('User（自己看自己）', () {
    test('完整字段解析', () {
      final user = User.fromJson(const {
        'userId': 1,
        'uniqueId': '76911262',
        'nickname': 'Mujin',
        'phone': '13800138000',
        'avatarUrl': 'http://x/a.jpg',
        'gender': 1,
        'age': 22,
        'genderPublic': true,
        'agePublic': false,
      });

      expect(user.gender, 1);
      expect(user.age, 22);
      expect(user.genderLabel, '男');
      expect(user.genderPublic, isTrue);
      expect(user.agePublic, isFalse);
    });

    test('未填写时 gender/age 为 null，且 genderLabel 为 null', () {
      final user = User.fromJson(const {
        'userId': 1,
        'uniqueId': '76911262',
        'nickname': 'Mujin',
        'phone': '13800138000',
      });

      expect(user.gender, isNull);
      expect(user.age, isNull);
      expect(user.genderLabel, isNull);
    });

    test('可见性字段缺失时默认 false（隐私默认关闭）', () {
      final user = User.fromJson(const {
        'userId': 1,
        'uniqueId': '76911262',
        'nickname': 'Mujin',
        'phone': '13800138000',
      });

      expect(user.genderPublic, isFalse,
          reason: '缺省必须是「不公开」，而不是恰好相反');
      expect(user.agePublic, isFalse);
    });

    test('gender=0（保密）不产生文案', () {
      final user = User.fromJson(const {
        'userId': 1,
        'uniqueId': '76911262',
        'nickname': 'Mujin',
        'phone': '13800138000',
        'gender': 0,
      });

      expect(user.gender, 0);
      expect(user.genderLabel, isNull, reason: '保密不应渲染成文字');
    });

    test('gender=2 显示女', () {
      final user = User.fromJson(const {
        'userId': 1,
        'uniqueId': '76911262',
        'nickname': 'Mujin',
        'phone': '13800138000',
        'gender': 2,
      });
      expect(user.genderLabel, '女');
    });
  });

  group('UserProfile（他人主页）', () {
    Map<String, dynamic> base() => {
          'userId': 2,
          'uniqueId': '11112222',
          'nickname': 'TesterB',
          'relation': 'friend',
        };

    test('对方公开 → 正常返回', () {
      final p = UserProfile.fromJson({
        ...base(),
        'gender': 1,
        'age': 20,
      });

      expect(p.gender, 1);
      expect(p.age, 20);
      expect(p.genderLabel, '男');
      expect(p.hasPublicProfileInfo, isTrue);
    });

    test('对方未公开 → 字段为 null（不是 0！）', () {
      final p = UserProfile.fromJson({
        ...base(),
        // 后端在不公开时**不返回这两个字段**
      });

      expect(p.gender, isNull,
          reason: '不公开必须是 null；兜底成 0 会让"保密"和"未设置"混淆');
      expect(p.age, isNull);
      expect(p.genderLabel, isNull);
      expect(p.hasPublicProfileInfo, isFalse);
    });

    test('只公开年龄、不公开性别', () {
      final p = UserProfile.fromJson({...base(), 'age': 19});

      expect(p.gender, isNull, reason: '性别未公开');
      expect(p.age, 19);
      expect(p.hasPublicProfileInfo, isTrue, reason: '有任一项就该展示这一块');
    });

    test('只公开性别、不公开年龄', () {
      final p = UserProfile.fromJson({...base(), 'gender': 2});

      expect(p.gender, 2);
      expect(p.age, isNull, reason: '年龄未公开');
      expect(p.genderLabel, '女');
    });

    test('gender=0（保密）时 genderLabel 为 null，但仍算"有信息"以外的情形', () {
      final p = UserProfile.fromJson({...base(), 'gender': 0});

      expect(p.gender, 0);
      expect(p.genderLabel, isNull);
      expect(p.hasPublicProfileInfo, isFalse,
          reason: '保密 + 无年龄 → 没有可展示的公开信息');
    });
  });
}
