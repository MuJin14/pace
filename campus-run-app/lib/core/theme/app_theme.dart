import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font_size.dart';
import 'app_spacing.dart';
import 'theme_palette.dart';

export 'app_font_size.dart';
export 'app_spacing.dart';
export 'theme_palette.dart';

/// 圆角：既有 4 档（8 / 12 / 16 / 24）+ 极小组件档。
class AppRadius {
  AppRadius._();

  static const double xxs = 6; // 迷你柱状图柱体
  static const double xs = 8;
  static const double sm = 12; // 按钮、输入框
  static const double md = 16; // 卡片
  static const double lg = 24; // 弹窗 / 大卡片
  static const double pill = 999; // 胶囊（chip / 药丸按钮）
}

/// 字重：统一 3 档（400 / 500 / 700）。
class AppFontWeight {
  AppFontWeight._();

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight bold = FontWeight.w700;
}

/// 阴影：极轻，不使用 Material 默认阴影。
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F241F1C), blurRadius: 10, offset: Offset(0, 4)),
  ];

  /// 中央凸起 FAB 的悬浮阴影（黑色 15%）。
  static const List<BoxShadow> fab = [
    BoxShadow(color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

/// 应用主题。
class AppTheme {
  AppTheme._();

  /// 手动构造 ColorScheme（禁用 fromSeed）。
  static final ColorScheme _scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryLight,
    onPrimaryContainer: AppColors.textPrimary,
    secondary: AppColors.secondary,
    onSecondary: AppColors.textPrimary,
    secondaryContainer: AppColors.secondaryLight,
    onSecondaryContainer: AppColors.textPrimary,
    error: AppColors.danger,
    surface: AppColors.card,
    onSurface: AppColors.textPrimary,
  );

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: _scheme,
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: AppFontSize.title,
          fontWeight: AppFontWeight.medium,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        // ⚠️ 必须显式声明：App 是浅色主题，状态栏文字/图标要用**深色**。
        //
        // 缺了它，系统沿用默认（深色主题下是浅色图标），
        // 于是白字画在奶油白背景上 —— 时间、电量几乎看不见。
        // 这个问题其实一直存在，只是以前登录页顶部是一大块橙色渐变，
        // 白图标在橙底上正好可见，把它掩盖住了；
        // 换成极简白底后就暴露出来了。
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark, // Android
          statusBarBrightness: Brightness.light, // iOS
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: const TextStyle(color: AppColors.textHint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          // 按钮专属字号 17（AppFontSize.button）
          textStyle: const TextStyle(
            fontSize: AppFontSize.button,
            fontWeight: AppFontWeight.bold,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        side: BorderSide.none,
        labelStyle: const TextStyle(fontWeight: AppFontWeight.medium),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: AppColors.onPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}
