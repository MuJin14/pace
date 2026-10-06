import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../network/media_url.dart';
import '../theme/app_theme.dart';
import 'brand_mark.dart';

/// 登录 / 注册共用的版式骨架（极简白底风）。
///
/// **为什么抽成一个组件**：这两个页面此前各写一份布局，
/// 于是出现了字号不一致、留白不一致、底部露出橙色条等一堆细节问题。
/// 版式只写一遍，两个页面就永远一致。
///
/// 视觉取向（用户选定「极简白底风」）：
///   · 奶油白底，**不用大面积橙色渐变**——那是上一版显土的主因；
///   · 橙色只出现在三处点缀：品牌标记、主按钮、文字链接；
///   · 表单不做浮动卡片：做成一张带描边的浅底面板，靠留白分层即可；
///   · 底部放一行极小的版本信息，避免页面下方出现「莫名空白」。
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.slogan,
    required this.title,
    required this.subtitle,
    required this.formChildren,
    this.eyeClosed = false,
  });

  /// 品牌标语，显示在图标下方。
  final String slogan;

  /// 表单区标题，如「欢迎回来」。
  final String title;

  /// 表单区副标题。
  final String subtitle;

  /// 输入框与按钮等。
  final List<Widget> formChildren;

  /// 是否让背景「闭眼」（用户正在输入密码）。
  ///
  /// 由**页面**持有这个状态并传进来，而不是在本组件内部自己管：
  /// 焦点属于具体某个输入框，页面本来就最清楚「哪个框被聚焦了」；
  /// 放在这里反而要多绕一层回调。
  ///
  /// 语义：鱼输入密码时，跑道上的圆点垂直压扁成一条横线，
  /// 与上方的跑道弧线组成一只**闭着的眼睛** ——
  /// 表达「密码是安全的，没人看着」。
  /// 用焦点变化驱动而不是监听输入内容：后者要在每次按键时重建整棵子树。
  final bool eyeClosed;

  @override
  Widget build(BuildContext context) {
    // 内容垂直居中 + 可滚动。
    //
    // LayoutBuilder 取到可用高度，ConstrainedBox 保证内容不足一屏时
    // 也能撑满并把内容居中；内容超出一屏（小屏 + 键盘弹出）时
    // 自然变成可滚动，不会溢出。这样高屏手机上不会在下方留一大块空白。
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 背景：会「跑」的跑道。
          //
          // 顶部 190px 内是一条横向循环滚动的波形跑道，上面有个原地不动的小人 ——
          // 侧滚错觉，看起来一直在往前跑。运动类 App 的静态首页容易显得死板，
          // 这一点动效成本极低（一个 CustomPainter + 一个 AnimationController），
          // 却能把「跑步」这件事直接表达出来。
          //
          // 高度 280px：跑道的波形 + 其**下方**的圆点都要装得下。
          // 圆点被刻意放在跑道下方（形成「上眼睑 + 眼睛」的关系），
          // 所以容器要比波形本身高出一截，否则圆点会被裁掉。
          // 仍然只占屏幕顶部一小块 —— 装饰一旦铺满全屏就会抢主体，
          // 也会盖住表单区域的阅读。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 280,
            child: IgnorePointer(
              child: RunningTrackBackdrop(eyeClosed: eyeClosed),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageWide,
                    // 顶部内边距 32 -> 16：跑道与 logo 整体上移，
                    // 与实测的「跑道 y≈97、logo y≈151」对齐。
                    AppSpacing.md,
                    AppSpacing.pageWide,
                    AppSpacing.lg,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - AppSpacing.md * 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _brandBlock(),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: AppFontSize.title,
                            fontWeight: AppFontWeight.bold,
                            color: AppColors.textPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: AppFontSize.body,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // 监听焦点：进入密码框就「闭眼」。
                        // 用 Focus(descendantsAreFocusable: true) 包住整个表单，
                        // 只关心「有没有焦点落在密码框上」，因此用 onFocusChange
                        // 判断是否有后代获得焦点即可 —— 但那样无法区分是哪个框，
                        // 所以这里改用显式的 FocusNode（见 AuthPasswordField）。
                        ...formChildren,
                        const SizedBox(height: AppSpacing.lg),
                        _footer(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandBlock() {
    return Column(
      children: [
        const BrandMark(size: 76, onGradient: false, color: AppColors.primary),
        const SizedBox(height: AppSpacing.md),
        const Text(
          '行迹',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: AppFontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: 10,
            // 字距会在右侧多出一个字的宽度，左移 5 补偿，视觉上居中
            height: 1.1,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          slogan,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: AppFontSize.caption,
            color: AppColors.textHint,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    // 一行极小的说明。现在它是居中内容块的一部分（不再吸底），
    // 所以不会再出现「页面下方一大块空白」的观感。
    return Text(
      '行迹 · 记录你的每一段行程',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        color: AppColors.textHint.withValues(alpha: 0.65),
        letterSpacing: 0.5,
      ),
    );
  }
}

/// 会「跑」的背景：一条横向循环滚动的跑道 + 原地不动的小人。
///
/// 视觉原理：**侧滚错觉**。跑道向左匀速滚动，小人在画面上固定不动，
/// 看起来就像小人一直在往前跑。这是 2D 游戏里最经典的「无限跑」表达方式，
/// 也正好对上「行迹」这个主题 —— 记录跑步的 App，首页就在跑。
///
/// 三个关键实现点（少一个都会露馅）：
///
/// 1. **必须无缝循环**。跑道由正弦波构成，且位移量正好推进一个波长的整数倍
///    （见 [_SupportTrailPainter._shift]），所以循环回起点时画面完全连续 ——
///    如果用随机折线或不匹配的位移，会看到明显跳变。
///
/// 2. **小人必须真的贴在跑道上**。它的 y 不是固定值，而是用**同一个波形函数**
///    在固定 x 处求出来的。否则滚动时小人会浮起来或陷进去，
///    「原地跑」的感觉立刻塌掉。
///
/// 3. **小人本身要有微动**。纯静止的圆点看起来像卡住了，
///    所以给它一个与跑道同步的上下起伏（步频感），
///    并且只在极小幅度内变化 —— 幅度大了会像在跳。
class RunningTrackBackdrop extends StatefulWidget {
  const RunningTrackBackdrop({super.key, required this.eyeClosed});

  /// 是否「闭眼」（用户正在输入密码）。
  final bool eyeClosed;

  @override
  State<RunningTrackBackdrop> createState() => _RunningTrackBackdropState();
}

class _RunningTrackBackdropState extends State<RunningTrackBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // 一个完整循环 4.2 秒。太快显得焦躁，太慢看不出在动。
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _RunningTrackPainter(
            progress: _controller.value,
            // 「减弱动态效果」是系统的无障碍开关：开启后必须停下动画。
            // 前庭功能敏感的用户会因为持续运动的背景而不适，
            // 这不是可选项，是必须尊重的系统设置。
            reduceMotion: MediaQuery.disableAnimationsOf(context),
            // 密码聚焦时「闭眼」（见 painter 里的说明）
            eyeClosed: widget.eyeClosed,
          ),
        );
      },
    );
  }
}

class _RunningTrackPainter extends CustomPainter {
  _RunningTrackPainter({
    required this.progress,
    required this.reduceMotion,
    required this.eyeClosed,
  });

  /// 0 → 1 的循环进度。
  final double progress;
  final bool reduceMotion;

  /// 是否处于「闭眼」状态（用户正在输入密码）。
  final bool eyeClosed;

  /// 跑道线宽（相对宽度的比例）。
  static const double _trackStroke = 0.030;

  /// 小人在画面上的水平位置（比例）。固定在中间偏左，
  /// 给右侧留出「前方还有路」的想象空间。
  static const double _runnerX = 0.52;

  /// 波形：两个正弦叠加，得到一个不太规则的起伏，比单一正弦自然。
  ///
  /// `phase` 是横向相位（已包含滚动位移）。
  /// 返回值是该处的相对高度（0 = 顶部，1 = 底部）。
  ///
  /// ⚠️ 振幅两度被调小，都是被实测逼出来的：
  ///   最初 0.16 / 0.055 → 小人在一个循环里上下移动 **68px**（背景仅 190px 高），
  ///   像在跳；压到 0.072 / 0.026 降到约 31px；
  ///   用户仍反馈「摆动范围要再小些，才能和跑道连成一个图形」，
  ///   于是再降到 0.048 / 0.017（约 21px）。
  ///
  /// 这一点很关键：**跑道 + 圆点要能被看成同一个图形**（想象成一只眼睛）。
  /// 波动一大，两者在视觉上就脱开了。
  /// 波形基线（容器内比例）。
  ///
  /// ⚠️ 这个数不再靠试，而是**按真机实测反推**：
  /// 在 1200×2670、DPR=3 的手机上量出
  ///   跑道中心 y ≈ 291 物理 = 97 逻辑
  ///   logo 中心 y ≈ 452 物理 = 151 逻辑
  /// 容器高 280 逻辑，因此基线取 97/280 ≈ 0.35。
  /// 圆点再落在基线下方一点（见 paint 里的偏移），
  /// 正好填在「跑道」与「logo」之间那段空隙里。
  /// 振幅在一个阶段内改过多次，最终口径由用户指定：
  /// **峰顶到峰谷的振幅 = 原来的 2/3**。
  ///
  /// 原系数 0.048 / 0.017（峰谷差 30.3 逻辑像素）
  ///   → 现系数 0.032 / 0.01133（峰谷差 20.2，正好 ×2/3）。
  ///
  /// 振幅调小后，圆点的上下起伏更收敛 —— 侧滚错觉更稳，
  /// 「横向在动、纵向基本不动」才是这个效果的核心。
  static double _wave(double x01, double phaseBase) {
    final t = (x01 + phaseBase) * 2 * math.pi;
    return 0.35 +
        math.sin(t * 1.0) * 0.032 +
        math.sin(t * 2.0 + 0.9) * 0.01133;
  }

  /// 滚动位移。**必须是整数个周期**，否则循环处会跳变。
  ///
  /// 波形里用了 1 倍和 2 倍频两个分量，所以位移量要是 1 的整数倍，
  /// 2 倍频自然也是整数倍（2 × 整数 = 整数），两个分量同时回到原位。
  /// 这里取 1 个周期：跑道看起来持续向**左**跑。
  double get _shift => progress * 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 走一个「减弱动态效果」时不滚动，只画静态跑道
    final phase = reduceMotion ? 0.0 : _shift;

    // ── 跑道 ────────────────────────────────────────────
    final track = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final x01 = i / steps;
      final y = _wave(x01, -phase) * h;
      // 横向多画出去一段，保证滚动时两端不会露空
      final x = (x01 - 0.25) * 1.5 * w;
      if (i == 0) {
        track.moveTo(x, y);
      } else {
        track.lineTo(x, y);
      }
    }

    canvas.drawPath(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w * _trackStroke
        ..color = AppColors.primaryLight.withValues(alpha: 0.42),
    );

    // ── 跑者 ────────────────────────────────────────────
    // y 用**同一个波形函数**求出来，保证它和跑道永远是一个整体。
    final runnerY = _wave(_runnerX, -phase) * h;

    // 步频起伏：幅度压得很小。
    // 侧滚错觉的关键是「横向在动、纵向不动」；
    // 而且纵向一动，圆点与跑道就不再像一个图形了。
    final bob = reduceMotion
        ? 0.0
        : math.sin(progress * 2 * math.pi * 2) * (w * 0.0035);

    final r = w * 0.020;

    // 圆心相对跑道中心线的下移量。
    //
    // 偏移 = 0.767 × 线宽（约 9.2 逻辑像素）。
    //
    // ⚠️ 这个值来回调过八次，最后**回退**到这一版。完整历程：
    //   1. 「半径 + 半个线宽」（约 38px）→ 圆点掉到跑道下方太远；
    //   2. 0.20 → 压在线上，太挤；
    //   3. 0.75 → 又太远，和跑道脱节；
    //   4. 0.50 → 与跑道融合，圆点「消失」；
    //   5. 0.65 → 仍偏上；
    //   6. 1.15 → 按真机实测反推（跑道基线 0.35），构图成立；
    //   7. 0.767 → 用户要求「下移量减少 1/3」（我按偏移量乘 2/3 实现，
    //      与用户本意不符）；
    //   8. −0.684 → 用户口径改为「最下沿 = 峰谷差的 2/3」，
    //      但圆点浮到跑道上方后**与 logo 标记粘连**；
    //   9. **回到 0.767**（本版）—— 用户确认以这一版的位置为准。
    //
    // 同时振幅按要求放大到 3/2，所以圆点的上下起伏比 1.6.5 更明显，
    // 但**平均位置**与 1.6.5 一致。
    final center = Offset(
      _runnerX * w,
      runnerY + bob + w * _trackStroke * 0.767,
    );

    if (eyeClosed) {
      // ── 闭眼：眼睛输入密码时「闭上」 ──────────────────────
      //
      // 圆点垂直压扁成一条横线，两端补小圆形成圆头 ——
      // 视觉上就是一条闭合的眼睑，与上方跑道弧线组成一只闭着的眼睛。
      // 语义上表达「密码是安全的，没人看着」。
      final lidPaint = Paint()..color = AppColors.primary;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: r * 2.0, height: r * 0.62),
          Radius.circular(r * 0.31),
        ),
        lidPaint,
      );
      return;
    }

    // ── 睁眼：瞳孔 ──────────────────────────────────────
    canvas.drawCircle(center, r, Paint()..color = AppColors.primary);

    // 高光：一点点内圈亮色，避免纯色块显得扁平
    canvas.drawCircle(
      Offset(center.dx - r * 0.28, center.dy - r * 0.30),
      r * 0.32,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _RunningTrackPainter old) =>
      old.progress != progress ||
      old.reduceMotion != reduceMotion ||
      old.eyeClosed != eyeClosed;
}

/// 极简输入框：白底 + 细描边，聚焦时描边变橙。
///
/// 刻意不用主题里的 `filled` 灰底 —— 白底细线更接近用户选的「极简白底风」，
/// 也和页面的奶油白背景有层次。
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.validator,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.maxLength,
    this.onFocusChange,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? Function(String?) validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;

  /// 焦点变化回调。
  ///
  /// 密码框用它驱动背景的「闭眼」状态（见 [AuthScaffold] 的说明）。
  /// 用焦点而不是「监听输入内容」：后者要在每次按键时重建整棵子树，
  /// 而焦点只在进入/离开时变化一次。
  final ValueChanged<bool>? onFocusChange;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  /// 自己持有 FocusNode。
  ///
  /// **交给 State 管理生命周期**，不要在每个 build 里 new 一个 ——
  /// 那样每次重建都会换掉焦点节点，键盘会反复收起、光标会跳。
  late final FocusNode _node = FocusNode()
    ..addListener(() => widget.onFocusChange?.call(_node.hasFocus));

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return TextFormField(
      controller: widget.controller,
      obscureText: widget.obscure,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      maxLength: widget.maxLength,
      focusNode: _node,
      style: const TextStyle(
        fontSize: AppFontSize.body,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: widget.hint,
        hintStyle: const TextStyle(color: AppColors.textHint),
        prefixIcon: Icon(widget.icon, size: 20, color: AppColors.textHint),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      validator: widget.validator,
    );
  }
}

/// 极简主按钮：橙色胶囊，带一点品牌色柔光。
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          // 光晕要克制：第一版 blur 18 / offset 6 看起来像按钮在发光，
          // 在极简白底上很突兀。现在只留一点点贴地的影子，
          // 目的是「看起来可按」，不是「看起来在发光」。
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
            foregroundColor: AppColors.onPrimary,
            elevation: 0,
            shape: const StadiumBorder(),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: AppFontSize.subtitle,
                    fontWeight: AppFontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 极简文字链接（无按钮内边距，像 iOS 的文本链）。
class AuthTextLink extends StatelessWidget {
  const AuthTextLink({
    super.key,
    required this.label,
    required this.onTap,
    this.color = AppColors.primary,
    this.fontSize = AppFontSize.body,
    this.bold = true,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final double fontSize;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            color: color,
            fontWeight: bold ? AppFontWeight.medium : AppFontWeight.regular,
          ),
        ),
      ),
    );
  }
}

/// 「我已阅读并同意《用户协议与隐私政策》」勾选框。
///
/// 登录与注册共用同一份，避免两处措辞或行为漂移。
/// 协议名是**可点的**，直接跳到完整条文 ——
/// 只给勾选框而不给阅读入口，等于强迫用户盲勾。
class AgreementCheckbox extends StatelessWidget {
  const AgreementCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const captionStyle = TextStyle(
      fontSize: AppFontSize.caption,
      color: AppColors.textSecondary,
      height: 1.45,
    );
    const linkStyle = TextStyle(
      fontSize: AppFontSize.caption,
      color: AppColors.primary,
      fontWeight: AppFontWeight.medium,
      height: 1.45,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 用 SizedBox 限定触控区，避免整行点击把正文的链接也吞掉
        SizedBox(
          width: 26,
          height: 26,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeColor: AppColors.primary,
            side: const BorderSide(color: AppColors.textHint, width: 1.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('我已阅读并同意', style: captionStyle),
                GestureDetector(
                  onTap: () => context.push('/privacy'),
                  child: const Text('《用户协议与隐私政策》', style: linkStyle),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 底部「已有账号 / 没有账号」一行。
class AuthSwitchRow extends StatelessWidget {
  const AuthSwitchRow({
    super.key,
    required this.prompt,
    required this.actionLabel,
    required this.onAction,
  });

  final String prompt;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          prompt,
          style: const TextStyle(
            fontSize: AppFontSize.body,
            color: AppColors.textSecondary,
          ),
        ),
        AuthTextLink(label: actionLabel, onTap: onAction),
      ],
    );
  }
}

/// 供页面使用的媒体地址工具（避免各页面重复 import）。
String? Function(String?) mediaResolver(Object ref) =>
    (url) => resolveMediaUrl(ref, url);
