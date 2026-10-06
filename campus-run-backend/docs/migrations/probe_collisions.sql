-- ════════════════════════════════════════════════════════════════════════
-- probe_collisions.sql —— 重排前的碰撞探针（只读，不改任何数据）
--
-- 目的：在真正执行 006 之前，一次性查出「重排后会不会撞唯一约束」。
--
-- ## 为什么需要它
--
-- 我在这次迁移里连续踩了三次同类问题：逐个表撞、逐个表补，
-- 每次都是跑到一半才报 `Duplicate entry`。根因是**检测方法错了**：
--
-- 我最初的检测是「按新 user_id 分组，看有没有重复」。但真正的碰撞
-- 形态是**交叉碰撞** —— A 的新值恰好等于 B 的旧值：
--
--     旧数据：user 4 有 (weekly, 2026-09-28, type 1)
--             user 1 有 (weekly, 2026-09-28, type 1)
--     重排后：user 4 → 1
--     结果：两行都变成 (user_id=1, weekly, 2026-09-28, 1)  ← 撞
--
-- 按新 user_id 分组看，一行来自 user 4、一行来自 user 1，看起来
-- 「各不相干」，但重排后它们的复合键一模一样。
--
-- 正确做法：把**完整的最终键**算出来，再查这个键有没有重复。
-- 这就是本脚本做的事。
--
-- ## 使用
--
--   mysql ... campus_run < probe_collisions.sql
--
-- 输出全是「无冲突」才能继续执行 006；否则要先处理冲突。
-- ════════════════════════════════════════════════════════════════════════

-- 映射：管理员优先（role DESC），其余按原 id 升序 —— 与 006 完全一致
-- ⚠️ 必须是**普通表**，不能是 TEMPORARY：
-- MySQL 不允许在同一条查询里两次打开同一个临时表
-- （`Can't reopen table: 'm1'`），而下面的 friendship / chat_preference
-- 检查都要 JOIN 它两次。普通表就正常了，用完显式 DROP。
DROP TABLE IF EXISTS `_probe_map`;
CREATE TABLE `_probe_map` (
    old_id BIGINT PRIMARY KEY,
    new_id BIGINT NOT NULL,
    UNIQUE KEY uk_new (new_id)
);
-- ⚠️ 序号从 0 开始，与 006 完全一致（ROW_NUMBER() 默认从 1 起，故减 1）
INSERT INTO `_probe_map` (old_id, new_id)
SELECT id, ROW_NUMBER() OVER (ORDER BY role DESC, id ASC) - 1 FROM `user`;

SELECT '映射条数' AS item, COUNT(*) AS value FROM `_probe_map`
UNION ALL SELECT '应等于用户数', (SELECT COUNT(*) FROM `user`);

-- ── 1) friendship：唯一键 (user_id, friend_id) ─────────────────────────
SELECT 'friendship 重排后重复键' AS 检查项,
       IFNULL(GROUP_CONCAT(CONCAT(u, '/', f, '×', c) SEPARATOR '  '), '无冲突') AS 结果
FROM (
    SELECT m1.new_id AS u, m2.new_id AS f, COUNT(*) AS c
    FROM friendship x
    JOIN `_probe_map` m1 ON m1.old_id = x.user_id
    JOIN `_probe_map` m2 ON m2.old_id = x.friend_id
    GROUP BY m1.new_id, m2.new_id
    HAVING COUNT(*) > 1
) t;

-- ── 2) chat_preference：唯一键 (user_id, friend_id) ────────────────────
SELECT 'chat_preference 重排后重复键' AS 检查项,
       IFNULL(GROUP_CONCAT(CONCAT(u, '/', f, '×', c) SEPARATOR '  '), '无冲突') AS 结果
FROM (
    SELECT m1.new_id AS u, m2.new_id AS f, COUNT(*) AS c
    FROM chat_preference x
    JOIN `_probe_map` m1 ON m1.old_id = x.user_id
    JOIN `_probe_map` m2 ON m2.old_id = x.friend_id
    GROUP BY m1.new_id, m2.new_id
    HAVING COUNT(*) > 1
) t;

-- ── 3) user_badge：唯一键 (user_id, badge_id) ─────────────────────────
SELECT 'user_badge 重排后重复键' AS 检查项,
       IFNULL(GROUP_CONCAT(CONCAT(u, '/', b, '×', c) SEPARATOR '  '), '无冲突') AS 结果
FROM (
    SELECT m.new_id AS u, x.badge_id AS b, COUNT(*) AS c
    FROM user_badge x
    JOIN `_probe_map` m ON m.old_id = x.user_id
    GROUP BY m.new_id, x.badge_id
    HAVING COUNT(*) > 1
) t;

-- ── 4) leaderboard_stats：唯一键 (user_id, scope, period, type) ────────
SELECT 'leaderboard_stats 重排后重复键' AS 检查项,
       IFNULL(GROUP_CONCAT(CONCAT(u, '/', sc, '/', p, '/', ty, '×', c) SEPARATOR '  '),
              '无冲突') AS 结果
FROM (
    SELECT m.new_id AS u, x.scope AS sc, x.period AS p, x.type AS ty, COUNT(*) AS c
    FROM leaderboard_stats x
    JOIN `_probe_map` m ON m.old_id = x.user_id
    GROUP BY m.new_id, x.scope, x.period, x.type
    HAVING COUNT(*) > 1
) t;

-- ── 5) user_stats / user_goal / device_token：主键或唯一键只有一列 ──────
--     只涉及 user_id 一列时，重排是**一对一**的，不可能产生重复；
--     这里只确认没有重复行本身。
SELECT 'user_stats 主键重复' AS 检查项,
       IFNULL(GROUP_CONCAT(CONCAT(u, '×', c) SEPARATOR '  '), '无冲突') AS 结果
FROM (
    SELECT m.new_id AS u, COUNT(*) AS c
    FROM user_stats x JOIN `_probe_map` m ON m.old_id = x.user_id
    GROUP BY m.new_id HAVING COUNT(*) > 1
) t;

-- ── 6) 孤儿引用（指向已删除用户的残留行）────────────────────────────────
--     这些行重排后会变成悬空引用，必须提前知道。
SELECT '孤儿引用' AS 检查项,
       CONCAT('friendship ', f1, ' / message ', f2, ' / activity ', f3,
              ' / leaderboard ', f4) AS 结果
FROM (
    SELECT
      (SELECT COUNT(*) FROM friendship x LEFT JOIN `user` u ON u.id = x.user_id WHERE u.id IS NULL) AS f1,
      (SELECT COUNT(*) FROM message x LEFT JOIN `user` u ON u.id = x.sender_id WHERE u.id IS NULL) AS f2,
      (SELECT COUNT(*) FROM activity x LEFT JOIN `user` u ON u.id = x.user_id WHERE u.id IS NULL) AS f3,
      (SELECT COUNT(*) FROM leaderboard_stats x LEFT JOIN `user` u ON u.id = x.user_id WHERE u.id IS NULL) AS f4
) t;

-- ── 7) 最终 id 分配预览 ────────────────────────────────────────────────
SELECT m.new_id AS 新id, LPAD(m.new_id, 8, '0') AS 新unique_id,
       u.nickname, u.role AS 管理员
FROM `_probe_map` m
JOIN `user` u ON u.id = m.old_id
ORDER BY m.new_id
LIMIT 12;

DROP TABLE `_probe_map`;
