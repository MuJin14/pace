// 对比度评估脚本：独立运行，打印 WCAG 2.1 对比度实测值。
//
// 运行（工作目录 campus-run-app）：
//   C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe run test/qa_contrast_check.dart
//
// 本文件刻意只用 ASCII 字符串作为标签，避免被非 UTF-8 工具链破坏。
// ignore_for_file: avoid_print
import 'dart:math' as math;

double _lin(int c) {
  final s = c / 255.0;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _lum(int hex) {
  final r = (hex >> 16) & 0xFF;
  final g = (hex >> 8) & 0xFF;
  final b = hex & 0xFF;
  return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);
}

double ratio(int fg, int bg) {
  final a = _lum(fg);
  final b = _lum(bg);
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// 把带 alpha 的前景色合成到背景色上，得到实际显示色。
int blend(int fg, int bg, double alpha) {
  int ch(int shift) {
    final f = (fg >> shift) & 0xFF;
    final b = (bg >> shift) & 0xFF;
    return (f * alpha + b * (1 - alpha)).round() & 0xFF;
  }

  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

void report(String label, int fg, int bg) {
  final r = ratio(fg, bg);
  final verdict = r >= 4.5
      ? 'PASS AA body'
      : (r >= 3.0 ? 'large-text only (3:1)' : 'FAIL min 3:1');
  print('${label.padRight(52)} ${r.toStringAsFixed(2)}:1   $verdict');
}

void main() {
  const primary = 0xFF8C42;
  const primaryDark = 0xE56A1E;
  const accentHot = 0xFF7A2E;
  const heroStart = 0xFF9E5E;
  const textPrimary = 0x2E2419;
  const textSecondary = 0x8C8075;
  const textHint = 0xB8AFA4;
  const card = 0xFFFFFF;
  const background = 0xFDF9F5;
  const surface = 0xF5F0EA;
  const deltaUp = 0x2FA36B;
  const danger = 0xEF4444;
  const medal = 0xE8A33D;
  const gold = 0xF59E0B;
  const secondary = 0x7DD3C0;

  print('=== text vs background (WCAG 2.1) ===');
  report('textPrimary #2E2419 on card #FFFFFF', textPrimary, card);
  report('textPrimary #2E2419 on bg #FDF9F5', textPrimary, background);
  report('textSecondary #8C8075 on card #FFFFFF', textSecondary, card);
  report('textSecondary #8C8075 on bg #FDF9F5', textSecondary, background);
  report('textSecondary #8C8075 on surface #F5F0EA', textSecondary, surface);
  report('textHint #B8AFA4 on card #FFFFFF', textHint, card);
  report('textHint #B8AFA4 on bg #FDF9F5', textHint, background);
  report('textHint #B8AFA4 on surface #F5F0EA', textHint, surface);
  report('primary #FF8C42 on card #FFFFFF', primary, card);
  report('accentHot #FF7A2E on card #FFFFFF', accentHot, card);
  report('deltaUp #2FA36B on chipGreenBg #EAF6EF', deltaUp, 0xEAF6EF);
  report('danger #EF4444 on chipRedBg #FDECEC', danger, 0xFDECEC);
  report('danger #EF4444 on card #FFFFFF', danger, card);
  report('medal #E8A33D on iconBgWarm #FFF6E6', medal, 0xFFF6E6);
  report('gold #F59E0B on card #FFFFFF', gold, card);
  report('secondary #7DD3C0 on card #FFFFFF', secondary, card);

  print('');
  print('=== white text on brand colors ===');
  report('white on primary #FF8C42', 0xFFFFFF, primary);
  report('white on primaryDark #E56A1E', 0xFFFFFF, primaryDark);
  report('white on heroStart #FF9E5E', 0xFFFFFF, heroStart);
  report('white on accentHot #FF7A2E', 0xFFFFFF, accentHot);

  print('');
  print('=== alpha-blended white on hero gradient mid #FF8C42 ===');
  const heroMid = 0xFF8C42;
  report('white 100% on heroMid', 0xFFFFFF, heroMid);
  report('white 85% on heroMid (hero subtitle)', blend(0xFFFFFF, heroMid, 0.85), heroMid);
  report('white 80% on heroMid (remaining km)', blend(0xFFFFFF, heroMid, 0.80), heroMid);
  report('white 70% on heroMid (unit / caption)', blend(0xFFFFFF, heroMid, 0.70), heroMid);

  print('');
  print('=== chart bars vs card ===');
  report('barPast #FFC79A on card #FFFFFF', 0xFFC79A, card);
  report('barEmpty #F2EDE8 on card #FFFFFF', 0xF2EDE8, card);
  report('accentHot #FF7A2E on card #FFFFFF (today bar)', accentHot, card);

  print('');
  print('=== candidate fixes ===');
  report('textSecondary #7A6E64 on card (candidate)', 0x7A6E64, card);
  report('textSecondary #7A6E64 on bg #FDF9F5 (candidate)', 0x7A6E64, background);
  report('textHint #9A9086 on card (candidate)', 0x9A9086, card);
  report('textHint #9A9086 on bg #FDF9F5 (candidate)', 0x9A9086, background);
}
