import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 用户协议与隐私政策。
///
/// **为什么必须存在**：本 App 收集定位信息（跑步轨迹）与手机号，按《个人信息保护法》
/// 与应用商店审核要求，必须在用户注册/登录前提供可查阅的协议与隐私政策，
/// 并说明收集范围、用途、存储与删除方式。缺失会直接被拒审。
///
/// 正式发布前请把下面文案替换为法务确认的版本，并把 [_updatedAt] 更新为生效日期。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _updatedAt = '2026-10-04';

  /// 联系方式。
  ///
  /// 必须是**真实可达**的邮箱：用户据此行使查阅/更正/删除权，
  /// 写个占位地址（原来是 support@example.com）等于让这些权利落空。
  static const String _contactEmail = 'mujin019@163.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('用户协议与隐私政策')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageWide,
          AppSpacing.md,
          AppSpacing.pageWide,
          AppSpacing.xl,
        ),
        children: const [
          _Meta(_updatedAt),
          _Section(
            1, '我们收集哪些信息',
            '1. 账号信息：手机号（用于登录与找回账号）、昵称、头像。\n'
                '2. 运动数据：跑步/骑行的轨迹坐标、距离、时长、配速、卡路里。\n'
                '3. 设备与日志：用于排查故障的客户端版本与错误日志。',
          ),
          _Section(
            2, '定位权限如何使用',
            '仅在**你主动点击「开始跑步/开始骑行」后**才采集定位，用于生成运动轨迹与统计距离。\n\n'
                '为保证锁屏或切换到其它应用时轨迹不中断，我们会在运动进行中通过前台服务持续采集定位，'
                '并在系统通知栏显示常驻提示；结束运动后立即停止采集。\n\n'
                '我们**不会**在未开始运动时后台采集你的位置。',
          ),
          _Section(
            3, '信息用于什么目的',
            '· 生成并展示你的运动记录与轨迹；\n'
                '· 计算排行榜名次、运动目标完成度与勋章；\n'
                '· 好友之间互看运动动态与聊天；\n'
                '· 识别异常数据（如明显不合理的轨迹），维护排行榜公平。',
          ),
          _Section(
            4, '我们如何共享信息',
            '我们**不向任何第三方出售**你的个人信息。仅在以下情况可见：\n\n'
                '· 排行榜：你的昵称、头像、专属 ID 与运动里程对其它用户可见；\n'
                '· 好友：你的运动记录对已互相同意的好友可见；\n'
                '· 法定情形：依法律法规或监管要求提供。',
          ),
          _Section(
            5, '数据存储与保留',
            '数据存储于中国境内的服务器。账号存续期间持续保留；'
                '你注销账号后，我们会在合理期限内删除或匿名化处理你的全部数据。',
          ),
          _Section(
            6, '你的权利',
            '· 查阅与更正：在「我的」页面查看账号信息；\n'
                '· 删除：在「我的 → 注销账号」中永久删除账号及全部数据（不可恢复）；\n'
                '· 撤回同意：可在系统设置中关闭定位权限，关闭后将无法记录运动轨迹；\n'
                '· 投诉与咨询：可通过下方邮箱联系我们。',
          ),
          _Section(
            7, '未成年人保护',
            '若你为未成年人，请在监护人同意并陪同下使用本服务。',
          ),
          _Section(
            8, '联系我们',
            '如对本协议或你的个人信息有任何疑问，请联系：$_contactEmail',
          ),
          _Footer(),
        ],
      ),
    );
  }
}

/// 顶部信息卡：生效日期 + 一句话说明这份文档为什么重要。
///
/// 原来只是一行灰色的「最近更新：xxxx-xx-xx」，夹在正文上方很不显眼。
/// 做成带品牌浅底的卡片后，它成为页面的视觉起点，
/// 也让用户一眼看出这是**具有效力的说明**，而不是普通的帮助文本。
class _Meta extends StatelessWidget {
  const _Meta(this.updatedAt);

  /// 生效日期。由页面传入而不是写死在文案里 ——
  /// 写死的话以后改日期要满文件找，容易漏。
  final String updatedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.xl),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.privacy_tip_outlined,
              size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '请在使用前仔细阅读',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '本说明涵盖我们收集哪些信息、定位权限如何使用，'
                  '以及你对这些信息的权利。生效日期：$updatedAt。',
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.index, this.title, this.body);

  /// 章节序号（从 1 开始）。渲染成圆形徽章。
  final int index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：圆形序号 + 标题。
          //
          // 直接用「一、二、三…」中文序号时，长标题在窄屏上换行会很难看，
          // 而且序号和文字挤在一起、层级感弱。改成徽章后：
          //   · 序号和标题分成两个视觉元素，扫读时更容易定位到第几节；
          //   · 颜色用品牌橙，让这份长文档仍有品牌一致性。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.primary,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppFontSize.subtitle,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // 正文缩进到与标题文字对齐（24 徽章 + 12 间距），
          // 形成清晰的「标题 — 内容」从属关系。
          Padding(
            padding: const EdgeInsets.only(left: 36),
            // 正文支持 `**粗体**`。
            //
            // ⚠️ 之前直接渲染纯字符串，于是页面里出现了字面的星号
            //（「仅在**你主动点击…**后才采集」）—— 看起来像没写完的草稿。
            // 协议正文是纯 Dart 字符串常量，没必要为它引入 markdown 依赖，
            // 用一个只认 `**` 的极小解析器就够了。
            child: _RichBody(body),
          ),
        ],
      ),
    );
  }
}

/// 极小的 `**粗体**` 解析器。
///
/// 只做一件事：把成对的 `**` 之间的文字加粗，其余保持常规字重。
class _RichBody extends StatelessWidget {
  const _RichBody(this.text);

  final String text;

  static const TextStyle _base = TextStyle(
    fontSize: AppFontSize.body,
    height: 1.6,
    color: AppColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    // split 之后：偶数下标是普通文本，奇数下标是加粗内容。
    // 这样天然处理「多处加粗」；未闭合时最后一段会被当作加粗，
    // 属于可接受的降级（不会崩，也不会漏字）。
    final parts = text.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(
        text: parts[i],
        style: i.isOdd
            ? _base.copyWith(
                fontWeight: AppFontWeight.bold,
                color: AppColors.textPrimary,
              )
            : _base,
      ));
    }
    return RichText(text: TextSpan(style: _base, children: spans));
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        '继续使用本服务即表示你已阅读并同意上述条款。',
        style: TextStyle(
          fontSize: AppFontSize.caption,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}
