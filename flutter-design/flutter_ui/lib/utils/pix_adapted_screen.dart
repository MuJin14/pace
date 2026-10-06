
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

class ScreenUtil {
  static ScreenUtil? _instance;

  ScreenUtil._internal();

  factory ScreenUtil() => _instance ??= ScreenUtil._internal();

  double get screenWidth => screenSize.width;

  double get screenHeight => screenSize.height;

  Size get screenSize => getScreenSize();

  set screenSize(Size size) {
    _screenSize = size;
  }

  Size? _screenSize;

  Size rootSize = Size(375, 812);

  double get wScale => screenWidth / (rootSize.width > 0 ? rootSize.width : 375);

  double get hScale => screenHeight / (rootSize.height > 0 ? rootSize.height : 812);

  static Future<void> init(BuildContext context) async {
    Size contentSize = Size(375, 812);
    if (!MediaQuery.of(context).size.isEmpty) {
      contentSize = MediaQuery.of(context).size;
    }
    ScreenUtil().screenSize = contentSize;
    return ensureScreenSize().then((_) {
      final view = View.maybeOf(context);
      if (view != null) {
        MediaQueryData deviceData = MediaQueryData.fromView(view);
        final Size deviceSize = deviceData.size.isEmpty ? contentSize : deviceData.size;
        ScreenUtil().screenSize = deviceSize;
      } else {
        ScreenUtil().screenSize = MediaQuery.of(context).size;
      }
    });
  }

  static Future<void> ensureScreenSize([
    ui.FlutterView? window,
    Duration duration = const Duration(milliseconds: 10),
  ]) async {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    binding.deferFirstFrame();

    await Future.doWhile(() {
      window ??= binding.platformDispatcher.implicitView;

      if (window == null || window!.physicalSize.isEmpty) {
        return Future.delayed(duration, () => true);
      }

      return false;
    });

    binding.allowFirstFrame();
  }

  Size getScreenSize() {
    if (_screenSize != null) {
      return _screenSize!;
    }
    // 获取物理像素尺寸
    Size physicalSize = ui.window.physicalSize;
    double physicalWidth = physicalSize.width;
    double physicalHeight = physicalSize.height;

    // 获取设备像素比
    double devicePixelRatio = ui.window.devicePixelRatio;

    // 计算逻辑像素尺寸
    double logicalWidth = physicalWidth / devicePixelRatio;
    double logicalHeight = physicalHeight / devicePixelRatio;
    _screenSize = Size(logicalWidth, logicalHeight);
    return _screenSize!;
  }

  double setWidth(num width) {
    if (kIsWeb) {
      return (rootSize.width > (_screenSize?.width ?? 0) && (_screenSize?.width ?? 0) > 0)
          ? width * wScale
          : width * 1.0;
    }
    return width * wScale;
  }

  double setHeight(num height) {
    if (kIsWeb) {
      return (rootSize.width > (_screenSize?.width ?? 0) && (_screenSize?.width ?? 0) > 0)
          ? height * wScale
          : height * 1.0;
    }
    return (_screenSize?.width ?? 0) > 1000 ? height * wScale : height * hScale;
  }

  double setSp(num sp) {
    if (kIsWeb) {
      return (rootSize.width > (_screenSize?.width ?? 0) && (_screenSize?.width ?? 0) > 0) ? sp * wScale : sp * 1.0;
    }
    return sp * (wScale);
  }
}

extension AdaptedScreenExtension on num {
  /// Creates adapt insets using r [SizeExtension].
  double get w => ScreenUtil().setWidth(this);

  double get h => ScreenUtil().setHeight(this);

  double get sp => ScreenUtil().setSp(this);

  double get minPx => min(ScreenUtil().setHeight(this), ScreenUtil().setWidth(this));
}



