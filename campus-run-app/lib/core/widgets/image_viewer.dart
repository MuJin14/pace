import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';

/// 打开全屏图片查看器。
///
/// [heroTag] 与缩略图上的 `Hero` 一致，用于打开时的放大过渡；传 null 则不做动画。
Future<void> showImageViewer(
  BuildContext context, {
  required String url,
  String? heroTag,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => ImageViewerPage(url: url, heroTag: heroTag),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// 全屏看图：支持缩放、双击放大、保存到相册。
///
/// **为什么必须自己实现**：聊天里的缩略图是 220px 的裁切展示，
/// 用户收到一张图却看不清、也拿不到原图 —— 图片功能等于只做了一半。
/// Flutter 没有内置的「图片查看器」，而引入第三方包只为这个功能不划算。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.url, this.heroTag});

  final String url;
  final String? heroTag;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final _transformController = TransformationController();

  /// 双击放大到 2.5 倍时，用于在「原始」与「放大」之间切换。
  TapDownDetails? _doubleTapDetails;

  bool _saving = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// 双击：已放大则复位，否则以点击处为中心放大。
  void _handleDoubleTap() {
    final current = _transformController.value;
    if (current.getMaxScaleOnAxis() > 1.01) {
      _transformController.value = Matrix4.identity();
      return;
    }
    final pos = _doubleTapDetails?.localPosition;
    if (pos == null) {
      _transformController.value = Matrix4.identity()..scale(2.5);
      return;
    }
    const scale = 2.5;
    _transformController.value = Matrix4.identity()
      ..translate(-pos.dx * (scale - 1), -pos.dy * (scale - 1))
      ..scale(scale);
  }

  /// 保存原图到相册。
  ///
  /// 用 [Gal] 而不是自己写文件：Android 10+ 起**不能**直接往相册目录写文件
  /// （分区存储），必须走 MediaStore；Gal 封装了这个差异，
  /// 并用 `Gal.hasAccess/requestAccess` 处理 Android 13+ 的权限变更。
  ///
  /// 为什么下载而不是直接拿缓存：`Image.network` 的缓存里拿不到原始字节，
  /// 而且保存必须是**原图**（不是缩略图），所以重新以绝对 URL 拉一次。
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    File? tmp;
    try {
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }

      final dir = await getTemporaryDirectory();
      // 固定文件名 + 时间戳：避免同名覆盖，也让相册里能看出是同一批
      tmp = File('${dir.path}/campus_run_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final resp = await Dio().download(widget.url, tmp.path);
      if (resp.statusCode != 200) {
        throw Exception('下载失败 HTTP ${resp.statusCode}');
      }

      await Gal.putImage(tmp.path);
      messenger.showSnackBar(const SnackBar(content: Text('已保存到相册')));
    } catch (e) {
      // 常见失败：用户拒绝相册权限、或系统相册不可用。
      // 给出可操作的说法，而不是抛一个 DioException 字符串。
      final msg = e.toString().contains('permission') ||
              e.toString().toLowerCase().contains('access')
          ? '没有相册权限，请在系统设置里允许后再试'
          : '保存失败，请稍后重试';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      debugPrint('[image-viewer] save failed: $e');
    } finally {
      // 临时文件不删：Gal 在部分机型上是异步落盘的，
      // 立刻删可能删掉还没写完的文件。系统会自己清临时目录。
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = widget.heroTag;
    final image = InteractiveViewer(
      transformationController: _transformController,
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (_, __, ___) => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
              SizedBox(height: AppSpacing.sm),
              Text('图片加载失败', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black38,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('查看图片', style: TextStyle(fontSize: AppFontSize.body)),
        actions: [
          // 正在保存时禁用按钮，避免重复下载
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download, color: Colors.white, size: 20),
            label: Text(
              _saving ? '保存中' : '保存',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        // 点一下关闭、双击缩放，符合微信/系统相册的习惯
        onTap: () => Navigator.of(context).maybePop(),
        onDoubleTapDown: (d) => _doubleTapDetails = d,
        onDoubleTap: _handleDoubleTap,
        child: SizedBox.expand(
          child: heroTag == null
              ? image
              : Hero(tag: heroTag, child: image),
        ),
      ),
    );
  }
}
