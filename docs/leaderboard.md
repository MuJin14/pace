# 排行榜与其余设计决策

排行榜的社交化增强与规范；好友拒绝逻辑；设计资产清单。

## 排行榜的社交化增强（已实现）
排行榜是**加好友的主要入口**，不只是看数字。

- 榜单每条记录额外返回三个字段：
  - `relation`（self / friend / pending_outgoing / pending_incoming / none）——
    由 `UserRelationResolver` 相对**当前登录用户**计算。
    **按钮状态一律以它为准**，前端不自行推断，否则会出现「显示加好友、点了报已存在」。
  - `gapToAheadMeters` / `gapToBehindMeters` —— 与前后名的距离差。
    **这是竞争感的关键**：只报总里程，用户不知道自己离前一名差多远、追不追得上。
    注意差距只在**本页内**计算；分页时本页第一条不会被误判成第 1 名（已有单测固化方向与非负性）。
- `getBoard` 新增 `currentUserId` 参数；接口用 `default` 方法保留了 5 参重载，
  避免改动既有调用点。
- 前端（`leaderboard_page.dart`）：
  - **领奖台**：前三名放大展示（冠军居中、台面最高、奖牌色），其余走列表，避免平铺罗列。
  - 每行**整行可点**进主页；行内按 `relation` 显示「加好友 / 发消息 / 通过 / 等待通过」。
  - **自己那一行高亮**（`AppColors.primaryLight`）+「我」标签 —— 榜单最核心的诉求是「我在哪」。
  - 副标题优先显示「距上一名还差 X」而不是 ID，让差距变成可追赶的目标。
  - `AppCard` 新增可选 `color` 参数（默认不变），用于行高亮。

## 排行榜规范（已实现，MySQL 方案）
- 支持日榜、周榜、滚动 30 天榜、自然月榜。
- **不使用 Redis**：排行榜数据完全基于 MySQL 的 `leaderboard_stats` 表实现。
- 实时更新用 `INSERT ... ON DUPLICATE KEY UPDATE`。
- 凌晨用定时任务（`task/LeaderboardScheduler`）重算滚动 30 天榜并清理过期数据。
- 查询直接走 SQL `ORDER BY ... LIMIT`。
- 历史方案「Redis ZSET，key `leaderboard:{period}:{type}`，`ZINCRBY`/`ZREVRANGE`」已废弃，勿再实现。

## 设计决策：好友拒绝逻辑
- 拒绝好友申请 = 删除 PENDING 记录，不保留 REJECTED 状态
- 理由：语义干净、允许重发、避免唯一键冲突
- 若将来需要「拒绝历史」或「黑名单」，单独建 user_block 表，不改 friendship

## 设计资产

设计资产清单见 [AGENTS.md](../AGENTS.md) 的「设计资产」一节 ——
本文件不再重复，避免两处清单不一致。

