import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 服务器地址的本地存储。
///
/// **为什么需要它**：API 地址原先只能靠编译期 `--dart-define` 注入，
/// 换一次网络（宿舍 WiFi / 校园网 / 热点）就要重新 `flutter build` 一遍，
/// 而开发调试时 IP 几乎每次都在变 —— 这是纯粹的浪费。
/// 现在改成运行时可改、持久化保存。
///
/// 优先级：本地保存的地址 > 编译期 `--dart-define` > 平台默认值。
abstract class ServerAddressStorage {
  Future<String?> read();
  Future<void> write(String address);
  Future<void> clear();
}

class PrefsServerAddressStorage implements ServerAddressStorage {
  PrefsServerAddressStorage([Future<SharedPreferences>? prefs])
      : _prefs = prefs ?? SharedPreferences.getInstance();

  static const String _key = 'server_base_url';

  final Future<SharedPreferences> _prefs;

  @override
  Future<String?> read() async {
    try {
      final prefs = await _prefs;
      final v = prefs.getString(_key);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String address) async {
    final prefs = await _prefs;
    await prefs.setString(_key, address.trim());
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_key);
  }
}

/// 测试与「不落盘」场景使用。
class InMemoryServerAddressStorage implements ServerAddressStorage {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String address) async => _value = address.trim();

  @override
  Future<void> clear() async => _value = null;
}

final serverAddressStorageProvider =
    Provider<ServerAddressStorage>((ref) => PrefsServerAddressStorage());

/// 规范化用户输入的地址。
///
/// 规则：
/// - 去掉首尾空白与结尾斜杠
/// - 没写协议时**自动推断**：IP / localhost / `.local` → `http://`；其余域名 → `https://`
///
/// ⚠️ **为什么必须区分 http 与 https**：
/// 原先一律补 `http://`，导致填 `api.hibiscus.wiki` 会变成
/// `http://api.hibiscus.wiki` —— 而 Cloudflare 的边缘**只接受 https**，
/// http 请求会一直超时。用户看到的现象是「地址填对了却连不上」，
/// 极难自查。真实项目里几乎只有 https，所以域名默认走 https。
///
/// 返回 null 表示不是合法地址。
String? normalizeServerAddress(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;

  // 去掉结尾斜杠，避免拼出 `//api/v1`
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return null;

  // 只写了协议（如 "http://"）时，补全后会变成 "http://http:"，
  // 而 Uri 会把 "http:" 当成合法主机名 —— 必须在补全前挡掉。
  if (s == 'http:' || s == 'https:' || s == 'http' || s == 'https') return null;

  if (!s.startsWith('http://') && !s.startsWith('https://')) {
    s = '${_inferScheme(s)}://$s';
  }

  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return null;
  // 主机名必须含字母或数字，挡掉 "http:" 这类伪主机
  if (!RegExp(r'[A-Za-z0-9]').hasMatch(uri.host)) return null;
  return s;
}

/// 推断缺失的协议。
///
/// 本地调试目标（IP、localhost）几乎都是明文 http；
/// 真实域名则几乎都是 https —— 猜错方向的代价很高（连不上），
/// 所以这里按「本地 → http，公网 → https」区分。
String _inferScheme(String s) {
  // 取出 host 部分（可能有 :port 与 /path）
  final host = s.split('/').first.split(':').first.toLowerCase();
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
    return 'http';
  }
  // IPv4 字面量
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
    return 'http';
  }
  // 局域网/内网域名（.local、无点号的主机名）也按 http 处理
  if (!host.contains('.')) return 'http';
  return 'https';
}
