import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/dio_client.dart';

/// 把服务端返回的媒体地址改写成「当前连接的服务器」上的地址。
///
/// **为什么必须做这件事（真实事故）**：
///
/// 服务端返回的头像是**绝对地址**，而且域名被写死在数据库里 ——
/// 数据库里存的是 `https://api.hibiscus.wiki:8443/uploads/avatar/xxx.jpg`
/// （由后端的 `PUBLIC_BASE_URL` 拼接）。
///
/// 一旦那个域名对客户端不可达（证书不被信任、DNS 被改、域名过期……），
/// 所有头像就全部加载失败。而 App 本身其实已经连上了服务器 ——
/// **只有图片加载走了另一个地址**，表现出来就是「能登录能聊天，但头像全是空白」。
///
/// 所以：不管服务端返回什么域名，都换成当前 `baseUrl` 的 scheme/host/port，
/// 只保留路径。这样「App 连得上服务器」就等价于「头像能加载」。
///
/// 规则：
/// - `http(s)://任意域名/路径` → `当前baseUrl/路径`
/// - 以 `/` 开头的相对路径 → `当前baseUrl/路径`
/// - 其它（如 `assets/...`、`data:`）原样返回
/// - 空值返回 null
String? resolveMediaUrl(Object ref, String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final raw = url.trim();

  // data: / 本地资源等不处理
  if (raw.startsWith('data:') || raw.startsWith('asset:')) return raw;

  String path;
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    final parsed = Uri.tryParse(raw);
    if (parsed == null || parsed.host.isEmpty) return raw;
    path = parsed.path;
    if (parsed.hasQuery) path = '$path?${parsed.query}';
  } else if (raw.startsWith('/')) {
    path = raw;
  } else {
    return raw;
  }

  final base = currentBaseUrl(ref);
  final b = Uri.tryParse(base);
  if (b == null || b.host.isEmpty) return raw;

  // ⚠️ 必须把 query 也带上：图片地址可能带签名/尺寸参数，
  //    只拼 path 会把参数静默丢掉，表现为「图能显示但尺寸/签名不对」。
  final q = path.indexOf('?');
  return Uri(
    scheme: b.scheme,
    host: b.host,
    port: b.hasPort ? b.port : null,
    path: q < 0 ? path : path.substring(0, q),
    query: q < 0 ? null : path.substring(q + 1),
  ).toString();
}

/// 给非 Riverpod 场景（测试、工具函数）用的纯函数版本。
///
/// 传入已知的 baseUrl，行为与 [resolveMediaUrl] 完全一致。
String? resolveMediaUrlWithBase(String base, String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final raw = url.trim();
  if (raw.startsWith('data:') || raw.startsWith('asset:')) return raw;

  String path;
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    final parsed = Uri.tryParse(raw);
    if (parsed == null || parsed.host.isEmpty) return raw;
    path = parsed.path;
    if (parsed.hasQuery) path = '$path?${parsed.query}';
  } else if (raw.startsWith('/')) {
    path = raw;
  } else {
    return raw;
  }

  final b = Uri.tryParse(base);
  if (b == null || b.host.isEmpty) return base + path;

  // 同上：query 必须保留
  final q = path.indexOf('?');
  return Uri(
    scheme: b.scheme,
    host: b.host,
    port: b.hasPort ? b.port : null,
    path: q < 0 ? path : path.substring(0, q),
    query: q < 0 ? null : path.substring(q + 1),
  ).toString();
}

/// 当前默认地址（给无法拿到 ref 的地方兜底）。
String get fallbackBaseUrl => AppConfig.baseUrl;

/// 把原图地址改写成**缩略图**接口地址。
///
/// **为什么需要**：服务端上行带宽只有约 0.2–0.46 MB/s，而聊天图上限 2MB。
/// 列表里直接拉原图，一张要 5–10 秒 —— 用户反馈的「加载图片巨慢」就是这个。
/// 缩略图 400px 通常 20–40KB，快两个数量级。
///
/// 返回 null 表示**不该用缩略图**（本地贴图 / data: / 非 uploads 资源），
/// 调用方应回退到原地址。
String? resolveThumbUrl(Object ref, String? url, {int width = 400}) =>
    _thumbFrom(currentBaseUrl(ref), resolveMediaUrl(ref, url), width);

/// [resolveThumbUrl] 的纯函数版本（测试用）。
String? resolveThumbUrlWithBase(String base, String? url, {int width = 400}) =>
    _thumbFrom(base, resolveMediaUrlWithBase(base, url), width);

String? _thumbFrom(String base, String? resolved, int width) {
  if (resolved == null) return null;
  // 本地贴图与内联资源不经过服务器
  if (resolved.startsWith('asset:') || resolved.startsWith('data:')) return null;

  final uri = Uri.tryParse(resolved);
  if (uri == null || uri.host.isEmpty) return null;
  const marker = '/uploads/';
  final idx = uri.path.indexOf(marker);
  if (idx < 0) return null; // 不是 uploads 下的资源（例如内置贴图）
  final relative = uri.path.substring(idx + marker.length);
  if (relative.isEmpty) return null;

  // path 用 encodeComponent：相对路径里可能有子目录（chat/xxx.jpg），
  // 直接拼进 query 会把 / 当成路径分隔符，必须转义。
  return '$base/api/v1/media/thumb?path=${Uri.encodeComponent(relative)}&w=$width';
}

/// Riverpod provider 形式的包装，便于在 widget 里 `ref.watch`。
final resolveMediaUrlProvider =
    Provider.family<String?, String?>((ref, url) => resolveMediaUrl(ref, url));
