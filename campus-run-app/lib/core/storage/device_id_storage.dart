import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备标识：一个**本地持久化的随机串**，用来区分「两个并存的登录」。
///
/// ## 为什么需要它
///
/// 服务端做单设备登录的规则是「在**另一台**设备上登录时递增令牌版本，
/// 让旧设备的令牌立即失效」。区分「同一台」与「另一台」全靠这个串。
///
/// 没有它会发生什么：同一台手机每次登录都被当成换设备，于是
/// **用户杀掉 App 重进就把自己踢下线** —— 而那是最正常的操作。
///
/// ## 为什么不用硬件 ID
///
/// 需求只是「在同一个安装内保持稳定」，不需要跨安装识别同一台手机：
///
///   · 硬件 ID（Android ID / IMEI）在 Android 10+ 上受限或需要额外权限，
///     而且属于隐私敏感数据，收集它没有任何收益；
///   · 卸载重装会被当成新设备 —— 这恰好是**正确**的语义：
///     重装后本来就应该重新登录。
///
/// 所以自己生成一串随机值存在本地即可，不上报任何硬件信息。
abstract class DeviceIdStorage {
  /// 读取设备标识；首次调用时生成并持久化。
  Future<String> get();

  /// 仅供测试：清掉已保存的值。
  Future<void> clear();
}

class PrefsDeviceIdStorage implements DeviceIdStorage {
  PrefsDeviceIdStorage([Future<SharedPreferences>? prefs])
      : _prefs = prefs ?? SharedPreferences.getInstance();

  static const String _key = 'device_id';

  final Future<SharedPreferences> _prefs;

  @override
  Future<String> get() async {
    final prefs = await _prefs;
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) return saved;
    final generated = _generate();
    await prefs.setString(_key, generated);
    return generated;
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_key);
  }

  /// 生成 32 位十六进制随机串。
  ///
  /// 用 [Random.secure] 而不是普通 [Random]：普通 Random 的种子在部分平台上
  /// 可预测，多台设备有概率生成同一个串 —— 那样两台手机会被误判成同一台，
  /// 单设备登录直接失效。这个串不参与任何加密运算，但**唯一性**很重要。
  static String _generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// 测试用：不落盘。
class InMemoryDeviceIdStorage implements DeviceIdStorage {
  InMemoryDeviceIdStorage([this._value]);

  String? _value;

  @override
  Future<String> get() async => _value ??= PrefsDeviceIdStorage._generate();

  @override
  Future<void> clear() async => _value = null;
}

final deviceIdStorageProvider =
    Provider<DeviceIdStorage>((ref) => PrefsDeviceIdStorage());
